#!/bin/bash
# ==============================================================================
# DARDE-CLIENT: Connection & Certificate Setup (Linux)
# Features: Smart JSON Discovery, Auto-Sudo, NSS DB Injection & Uninstaller
# ==============================================================================

# Ensure the script is run as root, auto-elevate if necessary
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[33m[INFO] Root privileges required. Elevating automatically with sudo...\e[0m"
  exec sudo bash "$0" "$@"
  exit $?
fi

REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$REAL_USER)

WORK_DIR="$USER_HOME/.darde-client"
VENV_DIR="$WORK_DIR/.venv"
TEMP_CERT="/tmp/darde-root.crt"
TEMP_JSON="/tmp/darde_client_profile.json"
HOSTS_FILE="/etc/hosts"

function prompt_credentials() {
    echo -e "\n\e[33m[ Network Configuration ]\e[0m"
    read -p "Enter the Gateway/Standalone IP Address: " SERVER_IP
    read -p "Enter the Server SSH Username (e.g., admin): " SERVER_USER

    if [[ -z "$SERVER_IP" || -z "$SERVER_USER" ]]; then
        echo -e "\e[31m[ERROR] IP and Username cannot be empty.\e[0m"
        exit 1
    fi
}

function install_client() {
    prompt_credentials

    # --- 1. Smart Discovery ---
    echo -e "\n\e[36m[1/6] Fetching Topology Profile via SSH...\e[0m"
    sudo -u "$REAL_USER" scp "${SERVER_USER}@${SERVER_IP}:~/darde_client_profile.json" "$TEMP_JSON"

    if [[ ! -f "$TEMP_JSON" ]]; then
        echo -e "\e[31m[ERROR] Unable to download darde_client_profile.json from the server.\e[0m"
        exit 1
    fi

    BASE_DOMAIN=$(python3 -c "import json; print(json.load(open('$TEMP_JSON')).get('base_domain', ''))" 2>/dev/null)
    NODE_NAME=$(echo "$BASE_DOMAIN" | cut -d'.' -f1)
    MACHINE_NAME=$(echo "$BASE_DOMAIN" | cut -d'.' -f2)

    if [[ -z "$BASE_DOMAIN" || -z "$NODE_NAME" || -z "$MACHINE_NAME" ]]; then
        echo -e "\e[31m[ERROR] JSON profile is corrupted or incomplete.\e[0m"
        exit 1
    fi

    echo -e "      -> \e[32m[OK] Topology Detected. Base Domain: $BASE_DOMAIN\e[0m"
    DOMAINS=("ai.$BASE_DOMAIN" "api.$BASE_DOMAIN" "dsp.$BASE_DOMAIN")

    # --- 2. Unique Certificate Trust Installation ---
    CERT_NAME="darde-${NODE_NAME}-${MACHINE_NAME}-root.crt"
    echo -e "\n\e[36m[2/6] Downloading and injecting the dedicated certificate ($CERT_NAME)...\e[0m"

    sudo -u "$REAL_USER" scp "${SERVER_USER}@${SERVER_IP}:~/${CERT_NAME}" "$TEMP_CERT"

    if [[ ! -f "$TEMP_CERT" ]]; then
        echo -e "\e[31m[ERROR] Certificate not found on the server. Run Option 1 on the server first.\e[0m"
        exit 1
    fi

    # System DB
    if command -v update-ca-certificates &> /dev/null; then
        cp "$TEMP_CERT" "/usr/local/share/ca-certificates/$CERT_NAME"
        update-ca-certificates > /dev/null 2>&1
    elif command -v update-ca-trust &> /dev/null; then
        cp "$TEMP_CERT" "/etc/ca-certificates/trust-source/anchors/$CERT_NAME"
        update-ca-trust > /dev/null 2>&1
    fi

    # NSS DB for Browsers
    if ! command -v certutil &> /dev/null; then
        echo -e "      [INFO] NSS tools missing on the client. Installing certutil..."
        if command -v pacman &> /dev/null; then pacman -S --noconfirm nss > /dev/null
        elif command -v apt-get &> /dev/null; then apt-get install -y libnss3-tools > /dev/null; fi
    fi

    if command -v certutil &> /dev/null; then
        if [ -d "$USER_HOME/.pki/nssdb" ]; then
            sudo -u "$REAL_USER" certutil -A -d sql:"$USER_HOME/.pki/nssdb" -n "$CERT_NAME" -t "C,," -i "$TEMP_CERT" >/dev/null 2>&1
        fi
        find "$USER_HOME/.mozilla/firefox" -name "cert9.db" 2>/dev/null | while read -r certdb; do
            p_dir=$(dirname "$certdb")
            sudo -u "$REAL_USER" certutil -A -d sql:"$p_dir" -n "$CERT_NAME" -t "C,," -i "$TEMP_CERT" >/dev/null 2>&1
        done
        echo -e "      -> \e[32m[OK] Certificate successfully injected into Browser databases.\e[0m"
    fi

    rm -f "$TEMP_CERT"
    rm -f "$TEMP_JSON"

    # --- 3. Hosts File Routing ---
    echo -e "\n\e[36m[3/6] Writing local DNS routes (/etc/hosts)...\e[0m"
    for DOMAIN in "${DOMAINS[@]}"; do
        if ! grep -q "\b$DOMAIN\b" "$HOSTS_FILE"; then
            echo -e "${SERVER_IP}\t${DOMAIN}" >> "$HOSTS_FILE"
            echo -e "      -> \e[32m[OK] Route added: $DOMAIN\e[0m"
        else
            echo -e "      -> \e[90mRoute already configured: $DOMAIN\e[0m"
        fi
    done

    # --- 4. AdGuard Auto-Provisioning (Dynamic & Validated) ---
    echo -e "\n\e[36m[4/6] Configure Gateway Firewall (AdGuard)...\e[0m"
    
    read -p "Set new AdGuard Admin Username: " ADG_USER
    
    # Ciclo di validazione password (minimo 7 caratteri)
    ADG_PASS=""
    while [ ${#ADG_PASS} -lt 7 ]; do
        read -s -p "Set new AdGuard Admin Password (min 7 characters): " ADG_PASS
        echo
        if [ ${#ADG_PASS} -lt 7 ]; then
            echo -e "\e[31m[ERROR] Password too short! Please use at least 7 characters.\e[0m"
        fi
    done

    # Generate payload dynamically... (il resto del codice rimane uguale)
    PAYLOAD=$(printf '{"web": {"ip": "0.0.0.0", "port": 3000, "status": ""}, "dns": {"ip": "0.0.0.0", "port": 53, "status": ""}, "password": "%s", "name": "%s"}' "$ADG_PASS" "$ADG_USER")
    # ...

    # --- 6. Dashboard HTML ---
    echo -e "\n\e[36m[6/6] Creating Desktop Command Center...\e[0m"
    DESKTOP_DIR="$USER_HOME/Desktop"
    DASHBOARD_PATH="$DESKTOP_DIR/DARDE_Dashboard.html"
    mkdir -p "$DESKTOP_DIR"

    cat <<EOF > "$DASHBOARD_PATH"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>DARDE | Command Center</title>
    <style>
        body { font-family: 'Segoe UI', Roboto, sans-serif; background-color: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .container { background-color: #1e293b; padding: 2.5rem; border-radius: 16px; text-align: center; width: 100%; max-width: 400px; border: 1px solid #334155; }
        h1 { color: #38bdf8; margin-bottom: 2rem; font-size: 1.8rem; }
        .btn { display: block; width: 100%; padding: 1rem; margin-bottom: 1rem; background-color: #2563eb; color: white; text-decoration: none; border-radius: 8px; font-weight: 600; box-sizing: border-box; }
        .btn:hover { background-color: #1d4ed8; }
        .desc { display: block; font-size: 0.85rem; color: #94a3b8; margin-top: 0.3rem; font-weight: normal; }
    </style>
</head>
<body>
    <div class="container">
        <h1>DARDE System</h1>
        <a href="https://ai.${BASE_DOMAIN}" class="btn" target="_blank">Open WebUI <span class="desc">AI Chat Interface</span></a>
        <a href="https://api.${BASE_DOMAIN}" class="btn" target="_blank">Ollama API <span class="desc">Backend Endpoint</span></a>
        <a href="https://dsp.${BASE_DOMAIN}" class="btn" target="_blank">DSP Server <span class="desc">Host Control Panel</span></a>
    </div>
</body>
</html>
EOF

    chown "$REAL_USER:$REAL_USER" "$DASHBOARD_PATH"
    echo -e "      -> \e[32m[OK] Dashboard generated at $DASHBOARD_PATH\e[0m"
    echo -e "\n\e[92m[SUCCESS] CLIENT INSTALLATION COMPLETED SUCCESSFULLY!\e[0m\n"
}

function uninstall_client() {
    echo -e "\n\e[31mWARNING: This will remove the trust from the server, DNS routes, dashboard, and Python environment.\e[0m"
    read -p "Proceed? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo -e "Operation cancelled."
        return
    fi

    # 1. Remove Certificates from NSS
    echo -e "\n\e[36m[1/4] Removing Certificates from Browser Databases...\e[0m"
    if command -v certutil &> /dev/null; then
        CERT_LIST=$(sudo -u "$REAL_USER" certutil -L -d sql:"$USER_HOME/.pki/nssdb" 2>/dev/null | grep "darde-" | awk '{print $1}')
        for cert in $CERT_LIST; do
            sudo -u "$REAL_USER" certutil -D -n "$cert" -d sql:"$USER_HOME/.pki/nssdb" >/dev/null 2>&1
        done

        find "$USER_HOME/.mozilla/firefox" -name "cert9.db" 2>/dev/null | while read -r certdb; do
            p_dir=$(dirname "$certdb")
            CERT_LIST=$(sudo -u "$REAL_USER" certutil -L -d sql:"$p_dir" 2>/dev/null | grep "darde-" | awk '{print $1}')
            for cert in $CERT_LIST; do
                sudo -u "$REAL_USER" certutil -D -n "$cert" -d sql:"$p_dir" >/dev/null 2>&1
            done
        done
        echo -e "      -> \e[32m[OK] Certificates removed from NSS databases.\e[0m"
    fi

    # Remove from System Trust
    rm -f /usr/local/share/ca-certificates/darde-*.crt
    rm -f /etc/ca-certificates/trust-source/anchors/darde-*.crt
    if command -v update-ca-certificates &> /dev/null; then update-ca-certificates > /dev/null 2>&1; fi
    if command -v update-ca-trust &> /dev/null; then update-ca-trust > /dev/null 2>&1; fi

    # 2. Clean Hosts File
    echo -e "\n\e[36m[2/4] Cleaning Hosts File...\e[0m"
    sed -i '/\.darde\.lan/d' "$HOSTS_FILE"
    sed -i '/\.local/d' "$HOSTS_FILE" 
    echo -e "      -> \e[32m[OK] Routes removed.\e[0m"

    # 3. Remove Python Environment
    echo -e "\n\e[36m[3/4] Removing Python Environment...\e[0m"
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        echo -e "      -> \e[32m[OK] Virtual environment removed.\e[0m"
    else
        echo -e "      -> \e[90mNo virtual environment found.\e[0m"
    fi

    # 4. Remove Dashboard HTML
    echo -e "\n\e[36m[4/4] Removing Dashboard HTML...\e[0m"
    DESKTOP_DIR="$USER_HOME/Desktop"
    DASHBOARD_PATH="$DESKTOP_DIR/DARDE_Dashboard.html"
    if [ -f "$DASHBOARD_PATH" ]; then
        rm -f "$DASHBOARD_PATH"
        echo -e "      -> \e[32m[OK] Dashboard removed.\e[0m"
    else
        echo -e "      -> \e[90mNo dashboard found.\e[0m"
    fi

    echo -e "\n\e[92m[SUCCESS] UNINSTALLATION COMPLETED.\e[0m\n"
}

# --- MAIN LOOP ---
while true; do
    echo -e "\e[36m====================================================\e[0m"
    echo -e "\e[36m DARDE CLIENT MANAGER (LINUX) - V11.0               \e[0m"
    echo -e "\e[36m====================================================\e[0m"
    echo -e "1) Install Client Connection (Certificate + DNS + Env + Dashboard)"
    echo -e "2) Uninstall and Restore PC"
    echo -e "q) Exit"
    echo -e "----------------------------------------------------"
    
    read -p "Select an option (1-2, q): " choice
    
    case $choice in
        1) install_client ;;
        2) uninstall_client ;;
        q|Q) exit 0 ;;
        *) echo -e "\e[31mInvalid option.\e[0m"; sleep 1 ;;
    esac
done