#!/bin/bash
# ==============================================================================
# DARDE-CLIENT: Connection & Certificate Setup (Linux)
# Features: Smart JSON Discovery, Auto-Sudo & Automated Firewall Provisioning
# ==============================================================================

# Ensure the script is run as root, auto-elevate if necessary
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[33m[INFO] Root privileges required. Elevating to sudo...\e[0m"
  exec sudo bash "$0" "$@"
  exit $?
fi

# Determine the real user (even when running under sudo) to avoid permission issues
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(eval echo ~$REAL_USER)

# Define Global Variables
WORK_DIR="$USER_HOME/.darde-client"
VENV_DIR="$WORK_DIR/.venv"
TEMP_CERT="/tmp/darde-root.crt"
TEMP_JSON="/tmp/darde_client_profile.json"
HOSTS_FILE="/etc/hosts"

clear
echo -e "\e[36m====================================================\e[0m"
echo -e "\e[36m DARDE CLIENT MANAGER (LINUX) - AUTOMATED SETUP     \e[0m"
echo -e "\e[36m====================================================\e[0m"

# --- 1. Prompt Credentials ---
echo -e "\n\e[33m[ Network Configuration ]\e[0m"
read -p "Enter the Gateway/Standalone IP Address: " SERVER_IP
read -p "Enter the Server SSH Username (e.g., admin): " SERVER_USER

if [[ -z "$SERVER_IP" || -z "$SERVER_USER" ]]; then
    echo -e "\e[31m[ERROR] IP and Username cannot be empty.\e[0m"
    exit 1
fi

# --- 2. Smart Discovery (Fetch JSON Profile) ---
echo -e "\n\e[36m[1/6] Fetching Topology Profile via SSH...\e[0m"
echo -e "\e[90m(You will be prompted for the SSH password)\e[0m"

sudo -u "$REAL_USER" scp "${SERVER_USER}@${SERVER_IP}:~/darde_client_profile.json" "$TEMP_JSON"

if [[ ! -f "$TEMP_JSON" ]]; then
    echo -e "\e[31m[ERROR] Failed to download JSON profile. Ensure the server wizard has been completed.\e[0m"
    exit 1
fi

# Parse the Base Domain and extract Node/Machine names
BASE_DOMAIN=$(python3 -c "import sys, json; print(json.load(open('$TEMP_JSON')).get('base_domain', ''))" 2>/dev/null)
NODE_NAME=$(echo "$BASE_DOMAIN" | cut -d'.' -f1)
MACHINE_NAME=$(echo "$BASE_DOMAIN" | cut -d'.' -f2)

if [[ -z "$BASE_DOMAIN" || -z "$NODE_NAME" || -z "$MACHINE_NAME" ]]; then
    echo -e "\e[31m[ERROR] Failed to parse base_domain from JSON.\e[0m"
    exit 1
fi

echo -e "      -> \e[32m[OK] Topology discovered. Base Domain: $BASE_DOMAIN\e[0m"
DOMAINS=("ai.$BASE_DOMAIN" "api.$BASE_DOMAIN" "dsp.$BASE_DOMAIN")

# --- 3. Unique Certificate Trust Installation ---
CERT_NAME="darde-${NODE_NAME}-${MACHINE_NAME}-root.crt"
echo -e "\n\e[36m[2/6] Fetching Unique Node Certificate ($CERT_NAME)...\e[0m"

sudo -u "$REAL_USER" scp "${SERVER_USER}@${SERVER_IP}:~/${CERT_NAME}" "$TEMP_CERT"

if [[ ! -f "$TEMP_CERT" ]]; then
    echo -e "\e[31m[ERROR] Failed to download certificate. Check if Core (Option 1) was installed on the server.\e[0m"
    exit 1
fi

if command -v update-ca-certificates &> /dev/null; then
    # Debian/Ubuntu
    cp "$TEMP_CERT" "/usr/local/share/ca-certificates/$CERT_NAME"
    update-ca-certificates > /dev/null 2>&1
elif command -v update-ca-trust &> /dev/null; then
    # Arch/Fedora/CentOS
    cp "$TEMP_CERT" "/etc/ca-certificates/trust-source/anchors/$CERT_NAME"
    update-ca-trust > /dev/null 2>&1
else
    echo -e "\e[33m[WARN] Could not detect certificate manager. Manual installation required.\e[0m"
fi

rm -f "$TEMP_CERT"
rm -f "$TEMP_JSON"
echo -e "      -> \e[32m[OK] Certificate installed.\e[0m"

# --- 4. Hosts File Routing ---
echo -e "\n\e[36m[3/6] Configuring Local DNS Routes (/etc/hosts)...\e[0m"
for DOMAIN in "${DOMAINS[@]}"; do
    if ! grep -q "\b$DOMAIN\b" "$HOSTS_FILE"; then
        echo -e "${SERVER_IP}\t${DOMAIN}" >> "$HOSTS_FILE"
        echo -e "      -> \e[32m[OK] Route added: $DOMAIN\e[0m"
    else
        echo -e "      -> \e[90mRoute already present: $DOMAIN\e[0m"
    fi
done

# --- 5. AdGuard Auto-Provisioning ---
echo -e "\n\e[36m[4/6] Initializing Gateway Firewall (AdGuard)...\e[0m"

PAYLOAD='{
    "web": {"ip": "0.0.0.0", "port": 3000, "status": ""},
    "dns": {"ip": "0.0.0.0", "port": 53, "status": ""},
    "password": "admin",
    "name": "admin"
}'

# Silent POST request to bypass the AdGuard setup wizard
curl -s -X POST "http://${SERVER_IP}:3000/control/install/configure" \
     -H "Content-Type: application/json" \
     -d "$PAYLOAD" > /dev/null 2>&1

echo -e "      -> \e[32m[OK] Firewall initialization packet sent.\e[0m"

# --- 6. Python Virtual Environment ---
echo -e "\n\e[36m[5/6] Setting up Python Virtual Environment...\e[0m"

if ! command -v python3 &> /dev/null; then
    echo -e "\e[31m[ERROR] Python3 is not installed.\e[0m"
    exit 1
fi

sudo -u "$REAL_USER" mkdir -p "$WORK_DIR"

if [ ! -d "$VENV_DIR" ]; then
    sudo -u "$REAL_USER" python3 -m venv "$VENV_DIR"
    echo -e "      -> \e[32m[OK] Virtual environment created.\e[0m"
else
    echo -e "      -> \e[90mVirtual environment already exists.\e[0m"
fi

echo -e "      -> \e[33mInstalling AI dependencies (chromadb, sentence-transformers)... Please wait.\e[0m"
sudo -u "$REAL_USER" "$VENV_DIR/bin/pip" install --upgrade pip > /dev/null 2>&1
if sudo -u "$REAL_USER" "$VENV_DIR/bin/pip" install chromadb sentence-transformers > /dev/null 2>&1; then
    echo -e "      -> \e[32m[OK] Dependencies installed successfully.\e[0m"
else
    echo -e "\e[31m      -> [ERROR] Failed to install dependencies.\e[0m"
fi

# --- 7. Dashboard HTML ---
echo -e "\n\e[36m[6/6] Creating Desktop Command Center...\e[0m"

DESKTOP_DIR="$USER_HOME/Desktop"
DASHBOARD_PATH="$DESKTOP_DIR/DARDE_Dashboard.html"

sudo -u "$REAL_USER" mkdir -p "$DESKTOP_DIR"

cat <<EOF > "$DASHBOARD_PATH"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
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
        <a href="https://api.${BASE_DOMAIN}" class="btn" target="_blank">Ollama API <span class="desc">Backend Services Endpoint</span></a>
        <a href="https://dsp.${BASE_DOMAIN}" class="btn" target="_blank">DSP Server <span class="desc">Host Management Panel</span></a>
    </div>
</body>
</html>
EOF

chown "$REAL_USER:$REAL_USER" "$DASHBOARD_PATH"
echo -e "      -> \e[32m[OK] Dashboard generated at $DASHBOARD_PATH\e[0m"

echo -e "\n\e[92m[SUCCESS] DARDE Client Setup Completed! You can now open the Dashboard.\e[0m\n"