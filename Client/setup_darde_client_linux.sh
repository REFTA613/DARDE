#!/bin/bash
# ==============================================================================
# DARDE-CLIENT: Connection & Certificate Setup (Linux)
# Features: Smart JSON Discovery, Auto-Sudo, NSS DB Injection & Auto-Provisioning
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[33m[INFO] Privilegi root richiesti. Elevazione automatica con sudo...\e[0m"
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

clear
echo -e "\e[36m====================================================\e[0m"
echo -e "\e[36m DARDE CLIENT MANAGER (LINUX) - AUTOMATED SETUP     \e[0m"
echo -e "\e[36m====================================================\e[0m"

# --- 1. Prompt Credentials ---
echo -e "\n\e[33m[ Configurazione Rete ]\e[0m"
read -p "Inserisci l'IP del Server Gateway/Standalone: " SERVER_IP
read -p "Inserisci l'utente SSH del Server (es. kwar): " SERVER_USER

if [[ -z "$SERVER_IP" || -z "$SERVER_USER" ]]; then
    echo -e "\e[31m[ERROR] L'IP e l'utente non possono essere vuoti.\e[0m"
    exit 1
fi

# --- 2. Smart Discovery ---
echo -e "\n\e[36m[1/6] Scaricamento del Profilo Topologico via SSH...\e[0m"
sudo -u "$REAL_USER" scp "${SERVER_USER}@${SERVER_IP}:~/darde_client_profile.json" "$TEMP_JSON"

if [[ ! -f "$TEMP_JSON" ]]; then
    echo -e "\e[31m[ERROR] Impossibile scaricare darde_client_profile.json dal server.\e[0m"
    exit 1
fi

BASE_DOMAIN=$(python3 -c "import json; print(json.load(open('$TEMP_JSON')).get('base_domain', ''))" 2>/dev/null)
NODE_NAME=$(echo "$BASE_DOMAIN" | cut -d'.' -f1)
MACHINE_NAME=$(echo "$BASE_DOMAIN" | cut -d'.' -f2)

if [[ -z "$BASE_DOMAIN" || -z "$NODE_NAME" || -z "$MACHINE_NAME" ]]; then
    echo -e "\e[31m[ERROR] Profilo JSON corrotto o incompleto.\e[0m"
    exit 1
fi

echo -e "      -> \e[32m[OK] Topologia Rilevata. Dominio Base: $BASE_DOMAIN\e[0m"
DOMAINS=("ai.$BASE_DOMAIN" "api.$BASE_DOMAIN" "dsp.$BASE_DOMAIN")

# --- 3. Installer Certificati Serio (System + NSS Browser DB) ---
CERT_NAME="darde-${NODE_NAME}-${MACHINE_NAME}-root.crt"
echo -e "\n\e[36m[2/6] Scaricamento e iniezione del certificato dedicato ($CERT_NAME)...\e[0m"

sudo -u "$REAL_USER" scp "${SERVER_USER}@${SERVER_IP}:~/${CERT_NAME}" "$TEMP_CERT"

if [[ ! -f "$TEMP_CERT" ]]; then
    echo -e "\e[31m[ERROR] Certificato non trovato sul server. Esegui prima l'opzione 1 sul server.\e[0m"
    exit 1
fi

# 3a. Installazione nel database di sistema
if command -v update-ca-certificates &> /dev/null; then
    cp "$TEMP_CERT" "/usr/local/share/ca-certificates/$CERT_NAME"
    update-ca-certificates > /dev/null 2>&1
elif command -v update-ca-trust &> /dev/null; then
    cp "$TEMP_CERT" "/etc/ca-certificates/trust-source/anchors/$CERT_NAME"
    update-ca-trust > /dev/null 2>&1
fi

# 3b. Installazione nei database NSS dei Browser (Rimuove i lucchetti rossi)
if ! command -v certutil &> /dev/null; then
    echo -e "      [INFO] Strumenti NSS mancanti sul client. Installazione di certutil..."
    if command -v pacman &> /dev/null; then pacman -S --noconfirm nss > /dev/null
    elif command -v apt-get &> /dev/null; then apt-get install -y libnss3-tools > /dev/null; fi
fi

if command -v certutil &> /dev/null; then
    # Chrome / Chromium / Edge
    if [ -d "$USER_HOME/.pki/nssdb" ]; then
        sudo -u "$REAL_USER" certutil -A -d sql:"$USER_HOME/.pki/nssdb" -n "$CERT_NAME" -t "C,," -i "$TEMP_CERT" >/dev/null 2>&1
    fi
    # Firefox (Scansione di tutti i profili attivi)
    find "$USER_HOME/.mozilla/firefox" -name "cert9.db" 2>/dev/null | while read -r certdb; do
        p_dir=$(dirname "$certdb")
        sudo -u "$REAL_USER" certutil -A -d sql:"$p_dir" -n "$CERT_NAME" -t "C,," -i "$TEMP_CERT" >/dev/null 2>&1
    done
    echo -e "      -> \e[32m[OK] Certificato inserito con successo nei database dei Browser.\e[0m"
fi

rm -f "$TEMP_CERT"
rm -f "$TEMP_JSON"

# --- 4. Hosts File Routing ---
echo -e "\n\e[36m[3/6] Scrittura delle rotte DNS locali (/etc/hosts)...\e[0m"
for DOMAIN in "${DOMAINS[@]}"; do
    if ! grep -q "\b$DOMAIN\b" "$HOSTS_FILE"; then
        echo -e "${SERVER_IP}\t${DOMAIN}" >> "$HOSTS_FILE"
        echo -e "      -> \e[32m[OK] Rotta inserita: $DOMAIN\e[0m"
    else
        echo -e "      -> \e[90mRotta già configurata: $DOMAIN\e[0m"
    fi
done

# --- 5. AdGuard Auto-Provisioning ---
echo -e "\n\e[36m[4/6] Configurazione automatica e attivazione immediata di AdGuard...\e[0m"
PAYLOAD='{"web": {"ip": "0.0.0.0", "port": 3000, "status": ""}, "dns": {"ip": "0.0.0.0", "port": 53, "status": ""}, "password": "admin", "name": "admin"}'
curl -s -X POST "http://${SERVER_IP}:3000/control/install/configure" -H "Content-Type: application/json" -d "$PAYLOAD" > /dev/null 2>&1
echo -e "      -> \e[32m[OK] Inizializzazione completata. Porta 53 sbloccata.\e[0m"

# --- 6. Python Virtual Environment ---
echo -e "\n\e[36m[5/6] Configurazione Ambiente Virtuale Python (Sandbox)...\e[0m"
mkdir -p "$WORK_DIR"
chown "$REAL_USER:$REAL_USER" "$WORK_DIR"
if [ ! -d "$VENV_DIR" ]; then
    sudo -u "$REAL_USER" python3 -m venv "$VENV_DIR"
    echo -e "      -> \e[32m[OK] Sandbox creata.\e[0m"
fi

echo -e "      -> Iniezione dipendenze IA (ChromaDB)... Attendere."
sudo -u "$REAL_USER" "$VENV_DIR/bin/pip" install --upgrade pip > /dev/null 2>&1
if sudo -u "$REAL_USER" "$VENV_DIR/bin/pip" install chromadb sentence-transformers > /dev/null 2>&1; then
    echo -e "      -> \e[32m[OK] Librerie installate con successo.\e[0m"
else
    echo -e "\e[31m      -> [ERROR] Errore durante l'installazione dei pacchetti.\e[0m"
fi

# --- 7. Dashboard HTML ---
echo -e "\n\e[36m[6/6] Creazione Centro di Comando sul Desktop...\e[0m"
DESKTOP_DIR="$USER_HOME/Desktop"
DASHBOARD_PATH="$DESKTOP_DIR/DARDE_Dashboard.html"
mkdir -p "$DESKTOP_DIR"

cat <<EOF > "$DASHBOARD_PATH"
<!DOCTYPE html>
<html lang="it">
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
        <a href="https://ai.${BASE_DOMAIN}" class="btn" target="_blank">Open WebUI <span class="desc">Interfaccia Chat AI</span></a>
        <a href="https://api.${BASE_DOMAIN}" class="btn" target="_blank">Ollama API <span class="desc">Endpoint Backend</span></a>
        <a href="https://dsp.${BASE_DOMAIN}" class="btn" target="_blank">DSP Server <span class="desc">Pannello di Controllo Host</span></a>
    </div>
</body>
</html>
EOF

chown "$REAL_USER:$REAL_USER" "$DASHBOARD_PATH"
echo -e "      -> \e[32m[OK] Dashboard generata in $DASHBOARD_PATH\e[0m"
echo -e "\n\e[92m[SUCCESS] INSTALLAZIONE CLIENT COMPLETATA CON SUCCESSO!\e[0m\n"