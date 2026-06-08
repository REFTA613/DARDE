#!/bin/bash

# ==============================================================================
# DARDE-CLIENT: Connection & Certificate Setup (Linux) - V11.0
# ==============================================================================

GLOBAL_SERVER_IP="10.0.0.50"
GLOBAL_SERVER_USER="admin"
GLOBAL_BASE_DOMAIN="master.server01.local"
DOMAINS=("ai.$GLOBAL_BASE_DOMAIN" "api.$GLOBAL_BASE_DOMAIN" "dsp.$GLOBAL_BASE_DOMAIN")
TEMP_CERT_PATH="/tmp/darde-root.crt"
HOSTS_PATH="/etc/hosts"
GLOBAL_WORK_DIR="$HOME/.darde-client"
GLOBAL_VENV_DIR="$GLOBAL_WORK_DIR/.venv"
GLOBAL_PIP_EXE="$GLOBAL_VENV_DIR/bin/pip"
GLOBAL_PYTHON_EXE="$GLOBAL_VENV_DIR/bin/python"

# --- Colors for Terminal Output ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# --- 0. Root Privilege Check ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run with sudo or as root.${NC}"
    exit 1
fi

# Get the real username behind sudo for user-space operations
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Adjust user-space paths based on the actual calling user
GLOBAL_WORK_DIR="$REAL_HOME/.darde-client"
GLOBAL_VENV_DIR="$GLOBAL_WORK_DIR/.venv"
GLOBAL_PIP_EXE="$GLOBAL_VENV_DIR/bin/pip"
GLOBAL_PYTHON_EXE="$GLOBAL_VENV_DIR/bin/python"

# --- CORE FUNCTIONS ---

prompt_credentials() {
    echo -e "\n${YELLOW}[ Network Configuration ]${NC}"
    read -r -p "Enter the Gateway/Standalone IP [Enter for: $GLOBAL_SERVER_IP]: " input_ip
    GLOBAL_SERVER_IP=${input_ip:-$GLOBAL_SERVER_IP}

    read -r -p "Enter the Server User [Enter for: $GLOBAL_SERVER_USER]: " input_user
    GLOBAL_SERVER_USER=${input_user:-$GLOBAL_SERVER_USER}

    read -r -p "Enter the Base Domain (e.g., master.server01.local) [Enter for: $GLOBAL_BASE_DOMAIN]: " input_domain
    if [ -not -z "$input_domain" ]; then
        GLOBAL_BASE_DOMAIN=$input_domain
        DOMAINS=("ai.$GLOBAL_BASE_DOMAIN" "api.$GLOBAL_BASE_DOMAIN" "dsp.$GLOBAL_BASE_DOMAIN")
    fi
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
        body {
            font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: #0f172a;
            color: #f8fafc;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }
        .dashboard-container {
            background-color: #1e293b;
            padding: 2.5rem;
            border-radius: 16px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            text-align: center;
            width: 100%;
            max-width: 400px;
            border: 1px solid #334155;
        }
        h1 {
            color: #38bdf8;
            margin-top: 0;
            margin-bottom: 2rem;
            font-size: 1.8rem;
            letter-spacing: 1px;
        }
        .btn {
            display: block;
            width: 100%;
            padding: 1rem;
            margin-bottom: 1rem;
            background-color: #2563eb;
            color: white;
            text-decoration: none;
            border-radius: 8px;
            font-size: 1.1rem;
            font-weight: 600;
            transition: all 0.2s ease;
            box-sizing: border-box;
            border: 1px solid transparent;
        }
        .btn:hover {
            background-color: #1d4ed8;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(37, 99, 235, 0.4);
        }
        .desc {
            display: block;
            font-size: 0.85rem;
            color: #94a3b8;
            margin-top: 0.3rem;
            font-weight: normal;
        }
        .footer {
            margin-top: 2rem;
            font-size: 0.75rem;
            color: #64748b;
        }
    </style>
</head>
<body>
    <div class="dashboard-container">
        <h1>DARDE System</h1>
        
        <a href="https://ai.${GLOBAL_BASE_DOMAIN}" class="btn" target="_blank">
            Open WebUI
            <span class="desc">AI Chat Interface</span>
        </a>
        
        <a href="https://api.${GLOBAL_BASE_DOMAIN}" class="btn" target="_blank">
            Ollama API
            <span class="desc">Backend Services Endpoint</span>
        </a>
        
        <a href="https://dsp.${GLOBAL_BASE_DOMAIN}" class="btn" target="_blank">
            DSP Server
            <span class="desc">Host Management Panel</span>
        </a>

        <div class="footer">DARDE Local Infrastructure • Secure Connection</div>
    </div>
</body>
</html>
EOF
    chown "$REAL_USER":"$REAL_USER" "$DASHBOARD_PATH"
    echo -e "      -> File 'DARDE_Dashboard.html' created on the Desktop."
}

install_ca_certificate() {
    # Detect package manager / distro family to copy to correct anchors folder
    if [ -d "/etc/ca-certificates/trust-source/anchors" ]; then
        # Arch Linux / CachyOS family
        CERT_DEST="/etc/ca-certificates/trust-source/anchors/darde-root.crt"
        cp "$TEMP_CERT_PATH" "$CERT_DEST"
        update-ca-trust
    elif [ -d "/usr/local/share/ca-certificates" ]; then
        # Debian / Ubuntu family
        CERT_DEST="/usr/local/share/ca-certificates/darde-root.crt"
        cp "$TEMP_CERT_PATH" "$CERT_DEST"
        update-ca-certificates
    elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
        # RHEL / Fedora / CentOS family
        CERT_DEST="/etc/pki/ca-trust/source/anchors/darde-root.crt"
        cp "$TEMP_CERT_PATH" "$CERT_DEST"
        update-ca-trust
    else
        echo -e "${RED}      -> [WARN] Unknown CA trust path. Certificate not added to system root.${NC}"
        return 1
    fi
    echo -e "${GREEN}      -> Certificate installed and system trust storage updated.${NC}"
    rm -f "$TEMP_CERT_PATH"
}

install_client() {
    prompt_credentials
    echo -e "\n${CYAN}[1/5] SSH connection for the certificate (Server Password Request)...${NC}"
    su - "$REAL_USER" -c "scp ${GLOBAL_SERVER_USER}@${GLOBAL_SERVER_IP}:~/DARDE-*-root.crt $TEMP_CERT_PATH"

    if [ ! -f "$TEMP_CERT_PATH" ]; then
        echo -e "${RED}[ERROR] Failed to download certificate. Check password or network.${NC}"
        return
    fi

    echo -e "\n${CYAN}[2/5] Trust installation in Linux Trust Store...${NC}"
    install_ca_certificate

    echo -e "\n${CYAN}[3/5] Local Route Configuration (Hosts File)...${NC}"
    for domain in "${DOMAINS[@]}"; do
        if ! grep -q "\b$domain\b" "$HOSTS_PATH"; then
            echo -e "$GLOBAL_SERVER_IP\t$domain" >> "$HOSTS_PATH"
            echo -e "${GREEN}      -> Route added: $domain${NC}"
        else
            echo -e "${GRAY}      -> Route already present: $domain${NC}"
        fi
    done

    echo -e "\n${CYAN}[4/5] Python Virtual Environment Setup...${NC}"
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}      -> [ERROR] Python3 is not installed or not in system PATH.${NC}"
        return
    fi

    if [ ! -d "$GLOBAL_WORK_DIR" ]; then
        su - "$REAL_USER" -c "mkdir -p $GLOBAL_WORK_DIR"
    fi

    if [ ! -d "$GLOBAL_VENV_DIR" ]; then
        su - "$REAL_USER" -c "python3 -m venv $GLOBAL_VENV_DIR"
        echo -e "${GREEN}      -> Virtual environment created in $GLOBAL_VENV_DIR${NC}"
    else
        echo -e "${GRAY}      -> Virtual environment already exists.${NC}"
    fi

    echo -e "${YELLOW}      -> Installing Python dependencies (chromadb, sentence-transformers)...${NC}"
    su - "$REAL_USER" -c "$GLOBAL_PIP_EXE install --upgrade pip --quiet"
    su - "$REAL_USER" -c "$GLOBAL_PIP_EXE install chromadb sentence-transformers --quiet"
    echo -e "${GREEN}      -> Dependencies installed successfully.${NC}"

    echo -e "\n${CYAN}[5/5] Dashboard HTML Creation...${NC}"
    create_dashboard

    echo -e "\n${GREEN}[OK] SETUP COMPLETED SUCCESSFULLY.${NC}"
}

uninstall_client() {
    echo -e "${RED}\nWARNING: This will remove the trust from the server, DNS routes, dashboard, and Python environment.${NC}"
    read -r -p "Proceed? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then return; fi

    echo -e "\n${CYAN}[1/4] Removing DARDE Certificates...${NC}"
    find /etc/ca-certificates/ /usr/local/share/ca-certificates/ /etc/pki/ca-trust/ -name "darde-root.crt" -delete 2>/dev/null
    if [ -d "/etc/ca-certificates/trust-source/anchors" ]; then update-ca-trust; fi
    if [ -d "/usr/local/share/ca-certificates" ]; then update-ca-certificates; fi
    echo -e "${GREEN}      -> System certificates cleaned.${NC}"

    echo -e "\n${CYAN}[2/4] Cleaning Hosts File...${NC}"
    sed -i "/${GLOBAL_BASE_DOMAIN}/d" "$HOSTS_PATH"
    echo -e "${GREEN}      -> Routes removed.${NC}"

    echo -e "\n${CYAN}[3/4] Removing Python Environment...${NC}"
    if [ -d "$GLOBAL_WORK_DIR" ]; then
        rm -rf "$GLOBAL_WORK_DIR"
        echo -e "${GREEN}      -> Sandbox folder removed.${NC}"
    else
        echo -e "${GRAY}      -> No environment found.${NC}"
    fi

    echo -e "\n${CYAN}[4/4] Removing Dashboard HTML...${NC}"
    DESKTOP_DIR="$REAL_HOME/Desktop"
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME/Scrivania"; fi
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME"; fi
    rm -f "$DESKTOP_DIR/DARDE_Dashboard.html"
    echo -e "${GREEN}      -> Dashboard removed.${NC}"

    echo -e "\n${GREEN}[OK] UNINSTALLATION COMPLETED.${NC}"
}

diagnose_and_heal() {
    echo -e "${CYAN}\n====================================================${NC}"
    echo -e "${CYAN} AUTO-HEAL: DIAGNOSTICS AND REPAIR${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "\n[TEST 1] Checking Hosts File: \c"
    missing=0
    for domain in "${DOMAINS[@]}"; do
        if ! grep -q "\b$domain\b" "$HOSTS_PATH"; then
            ((missing++))
            echo -e "$GLOBAL_SERVER_IP\t$domain" >> "$HOSTS_PATH"
        fi
    done
    if [ "$missing" -gt 0 ]; then
        echo -e "${YELLOW}[REPAIRED] Added $missing missing routes.${NC}"
    else
        echo -e "${GREEN}[OK] All routes are present.${NC}"
    fi

    echo -e "[TEST 2] Checking Certificate: \c"
    cert_found=0
    if find /etc/ca-certificates/ /usr/local/share/ca-certificates/ /etc/pki/ca-trust/ -name "darde-root.crt" | grep -q "darde-root.crt"; then
        cert_found=1
    fi

    if [ "$cert_found" -eq 0 ]; then
        echo -e "${RED}[FAILED] Certificate not found.${NC}"
        echo -e "${YELLOW}  -> [FIX] Trying to download and install automatically...${NC}"
        prompt_credentials
        su - "$REAL_USER" -c "scp ${GLOBAL_SERVER_USER}@${GLOBAL_SERVER_IP}:~/DARDE-*-root.crt $TEMP_CERT_PATH"
        if [ -f "$TEMP_CERT_PATH" ]; then
            install_ca_certificate
            echo -e "${GREEN}  -> [OK] Certificate restored.${NC}"
        else
            echo -e "${RED}  -> [ERROR] Fix failed. Unable to download.${NC}"
        fi
    else
        echo -e "${GREEN}[OK] Certificate valid.${NC}"
    fi

    echo -e "[TEST 3] Checking Server Proxy Reachability (Port 443): \c"
    if nc -z -w3 "$GLOBAL_SERVER_IP" 443 &>/dev/null; then
        echo -e "${GREEN}[OK] Server Online and Listening.${NC}"
    else
        echo -e "${RED}[ERROR] Server Offline or port 443 closed.${NC}"
    fi

    echo -e "[TEST 4] Checking Dashboard HTML: \c"
    DESKTOP_DIR="$REAL_HOME/Desktop"
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME/Scrivania"; fi
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME"; fi
    if [ ! -f "$DESKTOP_DIR/DARDE_Dashboard.html" ]; then
        echo -e "${YELLOW}[REPAIRED] Missing dashboard file. Recreating...${NC}"
        create_dashboard &>/dev/null
    else
        echo -e "${GREEN}[OK] Dashboard present.${NC}"
    fi

    echo -e "[TEST 5] Checking Python Environment: \c"
    if [ ! -d "$GLOBAL_VENV_DIR" ]; then
        echo -e "${RED}[FAILED] Virtual environment missing.${NC}"
        echo -e "${YELLOW}  -> [FIX] Rebuilding sandbox and injecting dependencies...${NC}"
        su - "$REAL_USER" -c "mkdir -p $GLOBAL_WORK_DIR && python3 -m venv $GLOBAL_VENV_DIR"
        su - "$REAL_USER" -c "$GLOBAL_PIP_EXE install --upgrade pip --quiet"
        su - "$REAL_USER" -c "$GLOBAL_PIP_EXE install chromadb sentence-transformers --quiet"
        echo -e "${GREEN}  -> [OK] Python environment completely restored.${NC}"
    else
        if su - "$REAL_USER" -c "$GLOBAL_PYTHON_EXE -c 'import chromadb' &>/dev/null"; then
            echo -e "${GREEN}[OK] Python environment is active and configured.${NC}"
        else
            echo -e "${YELLOW}[REPAIRED] Missing dependencies. Reinstalling...${NC}"
            su - "$REAL_USER" -c "$GLOBAL_PIP_EXE install chromadb sentence-transformers --quiet"
            echo -e "${GREEN}  -> [OK] Dependencies injected.${NC}"
        fi
    fi
    echo -e "\nDiagnostic Terminated."
}

show_debug() {
    echo -e "${CYAN}\n====================================================${NC}"
    echo -e "${CYAN} ADVANCED DEBUG${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "\n${YELLOW}--- CHECK ROUTES DNS (File Hosts) ---${NC}"
    for domain in "${DOMAINS[@]}"; do
        if grep -q "\b$domain\b" "$HOSTS_PATH"; then
            echo -e "${GREEN}  [ONLINE] $GLOBAL_SERVER_IP -> $domain${NC}"
        else
            echo -e "${RED}  [MISSING] No route for $domain${NC}"
        fi
    done

    echo -e "\n${YELLOW}--- CHECK CERTIFICATE INTEGRITY ---${NC}"
    cert_path=$(find /etc/ca-certificates/ /usr/local/share/ca-certificates/ /etc/pki/ca-trust/ -name "darde-root.crt" -print -quit 2>/dev/null)
    if [ -n "$cert_path" ]; then
        echo -e "${GREEN}  [ONLINE] Found certificate at: $cert_path${NC}"
    else
        echo -e "${RED}  [MISSING] No system root anchor found for DARDE.${NC}"
    fi

    echo -e "\n${YELLOW}--- CHECK DASHBOARD DESKTOP ---${NC}"
    DESKTOP_DIR="$REAL_HOME/Desktop"
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME/Scrivania"; fi
    if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$REAL_HOME"; fi
    if [ -f "$DESKTOP_DIR/DARDE_Dashboard.html" ]; then
        echo -e "${GREEN}  [ONLINE] DARDE_Dashboard.html is present on Desktop.${NC}"
    else
        echo -e "${RED}  [MISSING] DARDE_Dashboard.html not found.${NC}"
    fi

    echo -e "\n${YELLOW}--- PYTHON ENVIRONMENT ---${NC}"
    if [ -d "$GLOBAL_VENV_DIR" ]; then
        echo -e "${GREEN}  [PRESENT] Virtual Environment at $GLOBAL_VENV_DIR${NC}"
        if su - "$REAL_USER" -c "$GLOBAL_PYTHON_EXE -c 'import chromadb' &>/dev/null"; then
            echo -e "${GREEN}  [DEPENDENCIES OK] ChromaDB and sentence-transformers verified.${NC}"
        else
            echo -e "${RED}  [DEPENDENCIES MISSING] Environment is broken or packages are missing.${NC}"
        fi
    else
        echo -e "${RED}  [MISSING] Python sandbox not found.${NC}"
    fi
}

# --- MAIN LOOP ---
while true; do
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${CYAN} DARDE CLIENT MANAGER (LINUX) - V11.0${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo "1) Install Client Connection (Certificate + DNS + Env + Dashboard)"
    echo "2) Uninstall and Restore PC"
    echo "3) Diagnosis and Automatic Restore (Auto-Heal)"
    echo "4) Advanced Debug (Show status and anomalies)"
    echo "q) Exit "
    echo "----------------------------------------------------"
    read -r -p "Select an option (1-4, q): " chose

    case $chose in
        1) install_client; read -r -p "Press Enter to continue..." ;;
        2) uninstall_client; read -r -p "Press Enter to continue..." ;;
        3) diagnose_and_heal; read -r -p "Press Enter to continue..." ;;
        4) show_debug; read -r -p "Press Enter to continue..." ;;
        q|Q) exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
    esac
done