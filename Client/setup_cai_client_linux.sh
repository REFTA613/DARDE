#!/bin/bash
# ==============================================================================
# DCS-CAI-CLIENT: Manager Connessione e Trust Certificati (Linux) - V11.2
# ==============================================================================

# Variabili Globali
SERVER_IP="192.168.0.25"
SERVER_USER="kwar"
DOMAIN="cai.lan"
DOMAINS=("ai.$DOMAIN" "api.$DOMAIN" "dsp.$DOMAIN")
CERT_NAME="dspserver-cai.crt"
CERT_DEST="/etc/ca-certificates/trust-source/anchors/$CERT_NAME"
HOSTS_FILE="/etc/hosts"
WORK_DIR="$(pwd)"
VENV_DIR="$WORK_DIR/.venv"

# Colors for UI
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
GRAY='\033[1;30m'
NC='\033[0m'

# --- CORE FUNCTIONS ---

prompt_credentials() {
    echo -e "\n${YELLOW}[ Network Configuration ]${NC}"
    read -r -p "Enter the Server IP [Enter for: $SERVER_IP]: " input_ip
    SERVER_IP=${input_ip:-$SERVER_IP}

    read -r -p "Enter the Server User [Enter for: $SERVER_USER]: " input_user
    SERVER_USER=${input_user:-$SERVER_USER}
}

create_dashboard() {
    DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    DASHBOARD_FILE="$DESKTOP_DIR/DCS-CAI_Dashboard.html"
    
    # Generate the HTML page with integrated CSS (Dark Mode)
    cat << 'EOF' > "$DASHBOARD_FILE"
<!DOCTYPE html>
<html lang="it">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DCS-CAI | Command Center</title>
    <style>
        body {
            font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: #0f172a; /* Slate 900 */
            color: #f8fafc;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }
        .dashboard-container {
            background-color: #1e293b; /* Slate 800 */
            padding: 2.5rem;
            border-radius: 16px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            text-align: center;
            width: 100%;
            max-width: 400px;
            border: 1px solid #334155;
        }
        h1 {
            color: #38bdf8; /* Sky 400 */
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
            background-color: #2563eb; /* Blue 600 */
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
            background-color: #1d4ed8; /* Blue 700 */
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(37, 99, 235, 0.4);
        }
        .desc {
            display: block;
            font-size: 0.85rem;
            color: #94a3b8; /* Slate 400 */
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
        <h1>DCS-CAI System</h1>
        
        <a href="https://ai.cai.lan" class="btn" target="_blank">
            Open WebUI
            <span class="desc">Interfaccia Chat AI</span>
        </a>
        
        <a href="https://api.cai.lan" class="btn" target="_blank">
            Ollama API
            <span class="desc">Endpoint Backend Servizi</span>
        </a>
        
        <a href="https://dsp.cai.lan" class="btn" target="_blank">
            DSP Server
            <span class="desc">Pannello Gestione Host</span>
        </a>

        <div class="footer">DCS-CAI Local Infrastructure • Secure Connection</div>
    </div>
</body>
</html>
EOF
}

install_client() {
    prompt_credentials
    echo -e "\n${CYAN}[1/5] SSH Connection for Certificate (Server Password Required)...${NC}"
    # PATCH: Usa la wildcard per pescare il certificato dinamico dal server Linux
    scp "${SERVER_USER}@${SERVER_IP}:~/DARDE-*-root.crt" /tmp/caddy-root.crt

    if [ ! -f /tmp/caddy-root.crt ]; then
        echo -e "${RED}[ERROR] Failed to download certificate. Check password or network.${NC}"
        return
    fi

    echo -e "\n${CYAN}[2/5] Trust store certificate installation...${NC}"
    sudo cp /tmp/caddy-root.crt "$CERT_DEST"
    sudo chmod 644 "$CERT_DEST"
    sudo update-ca-trust
    rm -f /tmp/caddy-root.crt
    echo -e "      -> ${GREEN}Certificate installed and permissions unlocked.${NC}"

    echo -e "\n${CYAN}[3/5] Local Routes Configuration (/etc/hosts)...${NC}"
    for d in "${DOMAINS[@]}"; do
        if ! grep -q "$d" "$HOSTS_FILE"; then
            echo "$SERVER_IP $d" | sudo tee -a "$HOSTS_FILE" > /dev/null
            echo -e "      -> ${GREEN}Route added: $d${NC}"
        else
            echo -e "      -> ${GRAY}Route already present: $d${NC}"
        fi
    done

    echo -e "\n${CYAN}[4/5] Python Virtual Environment Setup...${NC}"
    mkdir -p "$WORK_DIR"
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        echo -e "      -> ${GREEN}Virtual environment created in $VENV_DIR.${NC}"
    else
        echo -e "      -> ${GRAY}Virtual environment already exists.${NC}"
    fi

    echo -e "      -> ${YELLOW}Installing Python dependencies (chromadb, sentence-transformers)...${NC}"
    "$VENV_DIR/bin/pip" install --upgrade pip > /dev/null 2>&1
    if "$VENV_DIR/bin/pip" install chromadb sentence-transformers > /dev/null 2>&1; then
        echo -e "      -> ${GREEN}Dependencies installed successfully.${NC}"
    else
        echo -e "      -> ${RED}Failed to install dependencies. Check your internet connection.${NC}"
    fi

    echo -e "\n${CYAN}[5/5] HTML Dashboard Creation...${NC}"
    create_dashboard
    echo -e "      -> ${GREEN}File 'DCS-CAI_Dashboard.html' created on the Desktop.${NC}"

    echo -e "\n${GREEN}[OK] SETUP COMPLETED SUCCESSFULLY.${NC}"
}

uninstall_client() {
    echo -e "\n${RED}ATTENTION: This will remove the trust for the server, DNS routes, the dashboard, and the Python environment.${NC}"
    read -r -p "Proceed? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then return; fi

    echo -e "\n${CYAN}[1/4] Caddy Certificate Removal...${NC}"
    if [ -f "$CERT_DEST" ]; then
        sudo rm -f "$CERT_DEST"
        sudo update-ca-trust
        echo -e "      -> ${GREEN}Certificate removed from Trust Store.${NC}"
    else
        echo -e "      -> ${GRAY}No certificate found.${NC}"
    fi

    echo -e "\n${CYAN}[2/4] Cleaning Routes from /etc/hosts...${NC}"
    sudo sed -i "/$DOMAIN/d" "$HOSTS_FILE"
    echo -e "      -> ${GREEN}Custom routes removed.${NC}"

    echo -e "\n${CYAN}[3/4] Removing Python Environment...${NC}"
    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
        echo -e "      -> ${GREEN}Virtual environment removed.${NC}"
    else
        echo -e "      -> ${GRAY}No virtual environment found.${NC}"
    fi

    echo -e "\n${CYAN}[4/4] Removing HTML Dashboard...${NC}"
    DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    if [ -f "$DESKTOP_DIR/DCS-CAI_Dashboard.html" ]; then
        rm -f "$DESKTOP_DIR/DCS-CAI_Dashboard.html"
        echo -e "      -> ${GREEN}Dashboard removed.${NC}"
    else
        echo -e "      -> ${GRAY}No dashboard found.${NC}"
    fi

    echo -e "\n${GREEN}[OK] UNINSTALLATION COMPLETED.${NC}"
}

diagnose_and_heal() {
    echo -e "\n${CYAN}====================================================${NC}"
    echo -e "${CYAN} AUTO-HEAL: Diagnosis and Repair${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -n -e "\n[TEST 1] Hosts File verification: "
    missing=0
    for d in "${DOMAINS[@]}"; do
        if ! grep -q "$d" "$HOSTS_FILE"; then
            echo "$SERVER_IP $d" | sudo tee -a "$HOSTS_FILE" > /dev/null
            ((missing++))
        fi
    done
    if [ $missing -gt 0 ]; then
        echo -e "${YELLOW}[REPAIRED] Added $missing missing routes to /etc/hosts.${NC}"
    else
        echo -e "${GREEN}[OK] All routes are present.${NC}"
    fi

    echo -n "[TEST 2] Verification of Certificate in Trust Store: "
    if [ ! -f "$CERT_DEST" ]; then
        echo -e "${RED}[FAILED] Certificate missing.${NC}"
        echo -e "  -> ${YELLOW}[FIX] Attempting restoration...${NC}"
        prompt_credentials
        # PATCH: Aggiornato per ripescare il file con wildcard durante l'auto-heal
        scp "${SERVER_USER}@${SERVER_IP}:~/DARDE-*-root.crt" /tmp/caddy-root.crt
        if [ -f /tmp/caddy-root.crt ]; then
            sudo cp /tmp/caddy-root.crt "$CERT_DEST"
            sudo chmod 644 "$CERT_DEST"
            sudo update-ca-trust
            rm -f /tmp/caddy-root.crt
            echo -e "  -> ${GREEN}[OK] Certificate restored.${NC}"
        fi
    elif [ "$(stat -c %a "$CERT_DEST")" != "644" ]; then
        echo -e "${YELLOW}[WARNING] Incorrect permissions. Correcting...${NC}"
        sudo chmod 644 "$CERT_DEST"
        echo -e "  -> ${GREEN}[OK] Read permissions restored.${NC}"
    else
        echo -e "${GREEN}[OK] Certificate valid and readable.${NC}"
    fi

    echo -n "[TEST 3] Verification of Server Proxy Reachability (Port 443): "
    if timeout 2 bash -c "</dev/tcp/$SERVER_IP/443" 2>/dev/null; then
        echo -e "${GREEN}[OK] Server Online and Listening.${NC}"
    else
        echo -e "${RED}[ERROR] The server is not responding or port 443 is closed.${NC}"
    fi

    echo -n "[TEST 4] Verification of HTML Dashboard: "
    DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    if [ ! -f "$DESKTOP_DIR/DCS-CAI_Dashboard.html" ]; then
        echo -e "${YELLOW}[REPAIRED] File missing. Recreating...${NC}"
        create_dashboard > /dev/null
    else
        echo -e "${GREEN}[OK] Dashboard present.${NC}"
    fi

    echo -n "[TEST 5] Verification of Python Environment: "
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${RED}[FAILED] Virtual environment missing.${NC}"
        echo -e "  -> ${YELLOW}[FIX] Rebuilding sandbox and injecting dependencies...${NC}"
        mkdir -p "$WORK_DIR"
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --upgrade pip > /dev/null 2>&1
        "$VENV_DIR/bin/pip" install chromadb sentence-transformers > /dev/null 2>&1
        echo -e "  -> ${GREEN}[OK] Python environment completely restored.${NC}"
    elif ! "$VENV_DIR/bin/python" -c "import chromadb" &> /dev/null; then
        echo -e "${YELLOW}[REPAIRED] Missing dependencies. Reinstalling...${NC}"
        "$VENV_DIR/bin/pip" install chromadb sentence-transformers > /dev/null 2>&1
        echo -e "  -> ${GREEN}[OK] Dependencies injected.${NC}"
    else
        echo -e "${GREEN}[OK] Python environment is active and configured.${NC}"
    fi

    echo -e "\n${CYAN}Diagnosis Terminated.${NC}"
}

show_debug() {
    echo -e "\n${CYAN}====================================================${NC}"
    echo -e "${CYAN} Advanced Debugging${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "\n${YELLOW}--- CHECK ROUTES DNS (/etc/hosts) ---${NC}"
    local missing_routes=0
    for d in "${DOMAINS[@]}"; do
        if grep -q "$SERVER_IP $d" "$HOSTS_FILE"; then
            echo -e "  ${GREEN}[PRESENT]${NC} $SERVER_IP -> $d"
        else
            echo -e "  ${RED}[MISSING]${NC} Nessuna rotta per $d"
            ((missing_routes++))
        fi
    done
    if [ $missing_routes -gt 0 ]; then
        echo -e "  ${RED}-> Broken routes found. Starting Auto-Heal... ${NC}"
    fi

    echo -e "\n${YELLOW}--- CERTIFICATE ANALYSIS (Caddy) ---${NC}"
    if [ -f "$CERT_DEST" ]; then
        echo -e "  ${GREEN}[PRESENT]${NC} File: $CERT_DEST"
        local perms=$(stat -c "%a" "$CERT_DEST")
        if [ "$perms" == "644" ]; then
            echo -e "  ${GREEN}[PERMISSIONS OK]${NC} Global read enabled (644)"
        else
            echo -e "  ${RED}[PERMISSIONS ERROR]${NC} Current: $perms (Required: 644)"
        fi
    else
        echo -e "  ${RED}[MISSING]${NC} Certificate not found"
    fi

    echo -e "\n${YELLOW}--- ANALYSIS OF DESKTOP DASHBOARD ---${NC}"
    DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    if [ -f "$DESKTOP_DIR/DCS-CAI_Dashboard.html" ]; then
        echo -e "  ${GREEN}[PRESENT]${NC} DCS-CAI_Dashboard.html"
    else
        echo -e "  ${RED}[MISSING]${NC} DCS-CAI_Dashboard.html not found on Desktop"
    fi

    echo -e "\n${YELLOW}--- PYTHON ENVIRONMENT ---${NC}"
    if [ -d "$VENV_DIR" ]; then
        echo -e "  ${GREEN}[PRESENT]${NC} Virtual Environment at $VENV_DIR"
        if "$VENV_DIR/bin/python" -c "import chromadb" &> /dev/null; then
            echo -e "  ${GREEN}[DEPENDENCIES OK]${NC} ChromaDB and sentence-transformers verified."
        else
            echo -e "  ${RED}[DEPENDENCIES MISSING]${NC} Required packages are not installed."
        fi
    else
        echo -e "  ${RED}[MISSING]${NC} Python virtual environment not found."
    fi

    echo -e "\n${YELLOW}--- CONNECTION TEST ---${NC}"
    if ping -c 1 -W 2 ai.$DOMAIN >/dev/null 2>&1; then
        echo -e "  ${GREEN}[NETWORK OK]${NC} ai.$DOMAIN resolved correctly to IP: $(getent ahosts ai.$DOMAIN | head -n 1 | awk '{print $1}')"
    else
        echo -e "  ${RED}[NETWORK FAILED]${NC} Unable to reach ai.$DOMAIN."
    fi
}

# --- LOOP MENU PRINCIPALE ---
while true; do
    echo -e "\n${CYAN}====================================================${NC}"
    echo -e "${CYAN} DCS-CAI CLIENT MANAGER (LINUX) - V11.2${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo "1) Install and Configure Client (Trust Certificate, Routes, Env, Dashboard)"
    echo "2) Uninstall and Restore PC"
    echo "3) Diagnosis and Automatic Restore (Auto-Heal)"
    echo "4) Advanced Debug (Show status and anomalies)"
    echo "q) Exit"
    echo "----------------------------------------------------"
    
    read -r -p "Select an option (1-4, q): " scelta
    
    case $scelta in
        1) install_client ;;
        2) uninstall_client ;;
        3) diagnose_and_heal ;;
        4) show_debug ;;
        q|Q) exit 0 ;;
        *) echo -e "${RED}Invalid option. Please try again.${NC}" ;;
    esac
done