#!/bin/bash

# ==============================================================================
# DARDE-CLIENT: Smart Service Discovery Setup (Linux) - V13.0
# ==============================================================================

GLOBAL_SERVER_IP="10.0.0.50"
GLOBAL_SERVER_USER="admin"
TEMP_CERT_PATH="/tmp/darde-root.crt"
TEMP_JSON_PATH="/tmp/darde_client_profile.json"
HOSTS_PATH="/etc/hosts"

# --- Colors for Terminal Output ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# --- 0. Root Privilege Check & Auto-Elevation ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${CYAN}[INFO] Administrative privileges required. Elevating...${NC}"
    exec sudo "$0" "$@"
    exit $?
fi

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# --- CORE FUNCTIONS ---

prompt_credentials() {
    echo -e "\n${YELLOW}[ Network Configuration ]${NC}"
    read -r -p "Enter the Server IP [Enter for: $GLOBAL_SERVER_IP]: " input_ip
    GLOBAL_SERVER_IP=${input_ip:-$GLOBAL_SERVER_IP}

    read -r -p "Enter the Server User [Enter for: $GLOBAL_SERVER_USER]: " input_user
    GLOBAL_SERVER_USER=${input_user:-$GLOBAL_SERVER_USER}
}

fetch_server_profile() {
    echo -e "\n${CYAN}[1/4] Connecting to Server to fetch Profile and Certificate...${NC}"
    
    # Doppio scp protetto solo dalle virgolette, senza backslash per l'asterisco
    scp -o StrictHostKeyChecking=accept-new "${GLOBAL_SERVER_USER}@${GLOBAL_SERVER_IP}:~/darde_client_profile.json" "$TEMP_JSON_PATH"
    scp -o StrictHostKeyChecking=accept-new "${GLOBAL_SERVER_USER}@${GLOBAL_SERVER_IP}:~/darde-root.crt" "$TEMP_CERT_PATH"

    if [ ! -f "$TEMP_CERT_PATH" ] || [ ! -f "$TEMP_JSON_PATH" ]; then
        echo -e "${RED}[ERROR] Failed to download files. Ensure you have run Option 1 on the Server first.${NC}"
        return 1
    fi

    # Native JSON parsing without external dependencies
    GLOBAL_BASE_DOMAIN=$(grep '"base_domain"' "$TEMP_JSON_PATH" | cut -d '"' -f 4)
    
    if [ -z "$GLOBAL_BASE_DOMAIN" ]; then
        echo -e "${RED}[ERROR] Invalid Profile JSON received.${NC}"
        return 1
    fi

    DOMAINS=("ai.$GLOBAL_BASE_DOMAIN" "api.$GLOBAL_BASE_DOMAIN" "dsp.$GLOBAL_BASE_DOMAIN")
    echo -e "${GREEN}  -> Target Infrastructure Discovered: $GLOBAL_BASE_DOMAIN${NC}"
    return 0
}

create_dashboard() {
    DESKTOP_DIR="$REAL_HOME/Desktop"
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME/Scrivania"; fi
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME"; fi

    DASHBOARD_PATH="$DESKTOP_DIR/DARDE_Dashboard.html"

    cat << EOF > "$DASHBOARD_PATH"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DARDE | Command Center</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background-color: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .dashboard-container { background-color: #1e293b; padding: 2.5rem; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); text-align: center; width: 100%; max-width: 400px; border: 1px solid #334155; }
        h1 { color: #38bdf8; margin-top: 0; margin-bottom: 2rem; font-size: 1.8rem; }
        .btn { display: block; width: 100%; padding: 1rem; margin-bottom: 1rem; background-color: #2563eb; color: white; text-decoration: none; border-radius: 8px; font-size: 1.1rem; font-weight: 600; transition: all 0.2s; box-sizing: border-box; }
        .btn:hover { background-color: #1d4ed8; transform: translateY(-2px); }
        .desc { display: block; font-size: 0.85rem; color: #94a3b8; margin-top: 0.3rem; font-weight: normal; }
        .footer { margin-top: 2rem; font-size: 0.75rem; color: #64748b; }
    </style>
</head>
<body>
    <div class="dashboard-container">
        <h1>DARDE System</h1>
        <a href="https://ai.${GLOBAL_BASE_DOMAIN}" class="btn" target="_blank">Open WebUI<span class="desc">AI Chat Interface</span></a>
        <a href="https://api.${GLOBAL_BASE_DOMAIN}" class="btn" target="_blank">Ollama API<span class="desc">Backend Services Endpoint</span></a>
        <a href="https://dsp.${GLOBAL_BASE_DOMAIN}" class="btn" target="_blank">DSP Server<span class="desc">Host Management Panel</span></a>
        <div class="footer">DARDE Local Infrastructure • Secure Connection</div>
    </div>
</body>
</html>
EOF
    chown "$REAL_USER":"$REAL_USER" "$DASHBOARD_PATH"
    echo -e "      -> File 'DARDE_Dashboard.html' created on the Desktop."
}

install_ca_certificate() {
    if [ -d "/etc/ca-certificates/trust-source/anchors" ]; then
        CERT_DEST="/etc/ca-certificates/trust-source/anchors/darde-root.crt"
        cp "$TEMP_CERT_PATH" "$CERT_DEST" && update-ca-trust
    elif [ -d "/usr/local/share/ca-certificates" ]; then
        CERT_DEST="/usr/local/share/ca-certificates/darde-root.crt"
        cp "$TEMP_CERT_PATH" "$CERT_DEST" && update-ca-certificates
    elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
        CERT_DEST="/etc/pki/ca-trust/source/anchors/darde-root.crt"
        cp "$TEMP_CERT_PATH" "$CERT_DEST" && update-ca-trust
    fi
    echo -e "${GREEN}      -> Certificate installed in system root.${NC}"
}

install_client() {
    prompt_credentials
    fetch_server_profile || return

    echo -e "\n${CYAN}[2/4] Trust installation in Linux Trust Store...${NC}"
    install_ca_certificate

    echo -e "\n${CYAN}[3/4] Local Route Configuration (Hosts File)...${NC}"
    for domain in "${DOMAINS[@]}"; do
        if ! grep -q "\b$domain\b" "$HOSTS_PATH"; then
            echo -e "$GLOBAL_SERVER_IP\t$domain" >> "$HOSTS_PATH"
            echo -e "${GREEN}      -> Route added: $domain${NC}"
        else
            echo -e "${GRAY}      -> Route already present: $domain${NC}"
        fi
    done

    echo -e "\n${CYAN}[4/4] Dashboard HTML Creation...${NC}"
    create_dashboard

    rm -f "$TEMP_CERT_PATH" "$TEMP_JSON_PATH"
    echo -e "\n${GREEN}[OK] SETUP COMPLETED SUCCESSFULLY.${NC}"
}

uninstall_client() {
    echo -e "${RED}\nWARNING: This will remove the trust from the server, DNS routes, and dashboard.${NC}"
    read -r -p "Proceed? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then return; fi

    prompt_credentials

    echo -e "\n${CYAN}[1/3] Removing DARDE Certificates...${NC}"
    find /etc/ca-certificates/ /usr/local/share/ca-certificates/ /etc/pki/ca-trust/ -name "darde-root.crt" -delete 2>/dev/null
    if [ -d "/etc/ca-certificates/trust-source/anchors" ]; then update-ca-trust; fi
    if [ -d "/usr/local/share/ca-certificates" ]; then update-ca-certificates; fi
    echo -e "${GREEN}      -> System certificates cleaned.${NC}"

    echo -e "\n${CYAN}[2/3] Cleaning Hosts File...${NC}"
    sed -i "/^${GLOBAL_SERVER_IP}/d" "$HOSTS_PATH"
    echo -e "${GREEN}      -> Routes pointing to ${GLOBAL_SERVER_IP} removed.${NC}"

    echo -e "\n${CYAN}[3/3] Removing Dashboard HTML...${NC}"
    DESKTOP_DIR="$REAL_HOME/Desktop"
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME/Scrivania"; fi
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME"; fi
    rm -f "$DESKTOP_DIR/DARDE_Dashboard.html"
    echo -e "${GREEN}      -> Dashboard removed.${NC}"

    echo -e "\n${GREEN}[OK] UNINSTALLATION COMPLETED.${NC}"
}

# --- MAIN LOOP ---
while true; do
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${CYAN} DARDE CLIENT MANAGER (LINUX) - V13.0 (Smart Discovery)${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo "1) Auto-Install Client Connection"
    echo "2) Uninstall and Restore PC"
    echo "q) Exit "
    echo "----------------------------------------------------"
    read -r -p "Select an option (1-2, q): " chose

    case $chose in
        1) install_client; read -r -p "Press Enter to continue..." ;;
        2) uninstall_client; read -r -p "Press Enter to continue..." ;;
        q|Q) exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
    esac
done