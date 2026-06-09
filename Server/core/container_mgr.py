"""
DCS-CAI-SERVER - Container Manager Module
Handles Podman volumes, images, container lifecycle, and dynamic Caddy routing.
"""

import subprocess
import time
import os
import config
import socket
from ai.model_mgr import select_initial_model

def check_grc():
    """Ensures grc is installed and configured for log colorization."""
    if subprocess.run(["which", "grc"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        print("[INFO] GRC not found, installing via pacman...")
        subprocess.run(["sudo", "pacman", "-S", "--noconfirm", "grc"], stdout=subprocess.DEVNULL)
        
    grc_conf_path = "/usr/share/grc/conf.dcscai"
    if not os.path.exists(grc_conf_path):
        print("[INFO] Generating GRC color rules for DCS-CAI...")
        rules = (
            "# DCS-CAI Log patterns\n"
            "regexp=\\[INFO\\]\n"
            "colours=cyan\n"
            "count=more\n"
            "---\n"
            "regexp=\\[OK\\]|SUCCESS\n"
            "colours=green\n"
            "count=more\n"
            "---\n"
            "regexp=\\[WARN\\]\n"
            "colours=yellow\n"
            "count=more\n"
            "---\n"
            "regexp=\\[ERROR\\]\n"
            "colours=red\n"
            "count=more\n"
        )
        
        with open("temp_grc_conf", "w") as f:
            f.write(rules)
            
        setup_cmd = (
            "sudo mkdir -p /usr/share/grc && "
            f"sudo mv temp_grc_conf {grc_conf_path} && "
            f"sudo chmod 644 {grc_conf_path} && "
            "sudo touch /etc/grc.conf && "
            "grep -q 'conf.dcscai' /etc/grc.conf || echo -e 'python3\\nconf.dcscai' | sudo tee -a /etc/grc.conf > /dev/null"
        )
        subprocess.run(setup_cmd, shell=True)

def wait_for_service_startup(port, host='127.0.0.1', retries=300, delay=2):
    """Polls a network socket to determine when a containerized service is fully ready."""
    print(f"\n[INFO] Waiting for container initialization on port {port}...")
    print("[INFO] (First absolute boot may take up to 10 minutes to download models)")
    
    for _ in range(retries):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            if s.connect_ex((host, port)) == 0:
                print(f"[OK] Service on port {port} is now fully operational!\n")
                return True
        time.sleep(delay)
        
    print(f"[WARN] Timeout: The service did not respond within the time limit.\n")
    return False

def configure_ufw():
    """
    Applies UFW firewall rules automatically to secure the infrastructure.
    """
    print("\n[INFO] Hardening System Firewall (UFW)...")
    ufw_commands = [
        ["ufw", "--force", "enable"],
        ["ufw", "limit", "22/tcp"],     
        ["ufw", "allow", "80/tcp"],     
        ["ufw", "allow", "443/tcp"],    
        ["ufw", "allow", "53/tcp"],     
        ["ufw", "allow", "53/udp"],     
        ["ufw", "allow", "3000/tcp"],   
        ["ufw", "allow", "8080/tcp"],   
        ["ufw", "allow", "11434/tcp"]   
    ]
    
    for cmd in ufw_commands:
        subprocess.run(["sudo"] + cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
    subprocess.run(["sudo", "ufw", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("[OK] Firewall rules strictly applied and UFW reloaded.")

def _run_podman(cmd, ignore_errors=False, capture_output=False, silent=False, **kwargs):
    """Executes Podman tasks natively to preserve TTY progress bars."""
    cmd_str = "podman " + " ".join(cmd)
    
    print(f"\033[0;35m  [DEPLOY] Running: {cmd_str}\033[0m")
    
    if capture_output:
        out_dest = subprocess.PIPE
        err_dest = subprocess.PIPE
    elif silent:
        out_dest = subprocess.DEVNULL
        err_dest = subprocess.DEVNULL
    else:
        out_dest = None
        err_dest = None 
        
    try:
        result = subprocess.run(
            ["sudo", "podman"] + cmd, 
            stdout=out_dest, 
            stderr=err_dest, 
            text=True if capture_output else False
        )
        
        if result.returncode != 0 and not ignore_errors:
            err_msg = result.stderr.strip() if capture_output and result.stderr else f"Exit code {result.returncode}"
            print(f"\033[0;31m  [ERROR] Component failed! Details: {err_msg}\033[0m")
            if not ignore_errors:
                raise RuntimeError(f"Podman task '{cmd[0]}' failed.")
        
        return result
        
    except KeyboardInterrupt:
        print("\n\033[0;33m  [WARN] Operation forcefully interrupted by user (Ctrl+C)!\033[0m")
        raise RuntimeError("Deployment aborted by user interrupt.")
        
    except Exception as e:
        if "aborted" in str(e).lower() or "failed" in str(e).lower():
            raise e
        print(f"\033[0;31m  [CRITICAL] Podman execution exception: {e}\033[0m")
        if not ignore_errors:
            raise RuntimeError(str(e))
        class FailedResult:
            returncode = 1
            stderr = str(e)
            stdout = ""
        return FailedResult()

def _ensure_volume(volume_name):
    """Creates a podman volume if it does not already exist."""
    result = _run_podman(["volume", "inspect", volume_name], capture_output=True, ignore_errors=True)
    if hasattr(result, 'returncode') and result.returncode != 0:
        print(f"[INFO] Creating persistent volume: {volume_name}")
        _run_podman(["volume", "create", volume_name])

def deploy_adguard():
    """Deploys the AdGuard Home container and applies the initial JSON configuration."""
    check_grc()
    print(f"\n[INFO] Deploying Security DNS ({config.CONTAINER_ADGUARD})...")
    _ensure_volume(config.VOL_ADGUARD_WORK)
    _ensure_volume(config.VOL_ADGUARD_CONF)

    _run_podman([
        "run", "-d", "--restart=always", "--replace",
        "--name", config.CONTAINER_ADGUARD,
        "--net=host",
        "-v", f"{config.VOL_ADGUARD_WORK}:/opt/adguardhome/work",
        "-v", f"{config.VOL_ADGUARD_CONF}:/opt/adguardhome/conf",
        "docker.io/adguard/adguardhome"
    ])
    
    time.sleep(3)
    print("[INFO] Applying default AdGuard interface configuration...")
    
    curl_cmd = [
        "sudo", "curl", "-s", "-X", "POST", "http://127.0.0.1:3000/control/install/configure",
        "-H", "Content-Type: application/json",
        "-d", '{"web": {"ip": "0.0.0.0", "port": 3000, "status": ""}, "dns": {"ip": "0.0.0.0", "port": 53, "status": ""}, "password": "admin", "name": "admin"}'
    ]
    subprocess.run(curl_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    _run_podman(["restart", config.CONTAINER_ADGUARD], ignore_errors=True)
    print(f"[OK] {config.CONTAINER_ADGUARD} deployed successfully.")

def deploy_caddy():
    """Deploys Caddy proxy and builds routing configs matching active config.py domains."""
    print(f"\n[INFO] Deploying Reverse Proxy ({config.CONTAINER_CADDY})...")
    _ensure_volume(config.VOL_CADDY_DATA)
    _ensure_volume(config.VOL_CADDY_CONF)

    domain_dsp = getattr(config, 'DOMAIN_DSP', 'dsp.darde.lan')
    domain_ai = getattr(config, 'DOMAIN_AI', 'ai.darde.lan')
    domain_api = getattr(config, 'DOMAIN_API', 'api.darde.lan')

    print(f"[INFO] Writing dynamic routing rules for: {domain_dsp}, {domain_ai}, {domain_api}")
    
    # FIX: Isola il blocco di trasporto ed evita l'errore 500 in modalità Standalone
    if getattr(config, 'NODE_ROLE', 'standalone') == 'gateway':
        compute_ip = getattr(config, 'COMPUTE_NODE_IP', '127.0.0.1')
        api_proxy_block = (
            f"        reverse_proxy https://{compute_ip}:8443 {{\n"
            f"                header_up Host \"localhost\"\n"
            f"                header_up Origin \"http://localhost\"\n"
            f"                transport http {{\n"
            f"                        tls_insecure_skip_verify\n"
            f"                }}\n"
            f"        }}\n"
        )
    else:
        api_proxy_block = (
            f"        reverse_proxy 127.0.0.1:11434 {{\n"
            f"                header_up Host \"localhost\"\n"
            f"                header_up Origin \"http://localhost\"\n"
            f"        }}\n"
        )

    caddyfile_content = (
        f"{domain_dsp} {{\n"
        f"        tls internal\n"
        f"        log\n"
        f"        reverse_proxy 127.0.0.1:3000\n"
        f"}}\n"
        f"{domain_ai} {{\n"
        f"        tls internal\n"
        f"        log\n"
        f"        reverse_proxy 127.0.0.1:8080\n"
        f"}}\n"
        f"{domain_api} {{\n"
        f"        tls internal\n"
        f"        log\n"
        f"{api_proxy_block}"
        f"}}\n"
    )

    caddy_dir = os.path.dirname(config.CADDYFILE_PATH)
    subprocess.run(["sudo", "mkdir", "-p", caddy_dir], stdout=subprocess.DEVNULL)
    
    with open("temp_Caddyfile", "w") as f:
        f.write(caddyfile_content)
    subprocess.run(["sudo", "mv", "temp_Caddyfile", config.CADDYFILE_PATH], stdout=subprocess.DEVNULL)

    _run_podman([
        "run", "-d", "--restart=always", "--replace",
        "--name", config.CONTAINER_CADDY,
        "--net=host",
        "-v", f"{config.CADDYFILE_PATH}:/etc/caddy/Caddyfile:Z",
        "-v", f"{config.VOL_CADDY_DATA}:/data",
        "-v", f"{config.VOL_CADDY_CONF}:/config",
        "docker.io/library/caddy"
    ])
    
    print("[INFO] Waiting for Caddy to generate Internal Root Certificate...")
    ca_internal_path = "/data/caddy/pki/authorities/local/root.crt"
    cert_ready = False
    
    for _ in range(10):
        check = _run_podman(["exec", config.CONTAINER_CADDY, "stat", ca_internal_path], capture_output=True, ignore_errors=True)
        if hasattr(check, 'returncode') and check.returncode == 0:
            cert_ready = True
            break
        time.sleep(2)

    if cert_ready:
        home_dir = os.path.expanduser("~")
        
        
        node_name = getattr(config, 'NODE_NAME', 'master')
        machine_name = getattr(config, 'MACHINE_NAME', 'server')
        cert_filename = f"darde-{node_name}-{machine_name}-root.crt"
        dest_cert = os.path.join(home_dir, cert_filename)
        
        subprocess.run(["sudo", "podman", "cp", f"{config.CONTAINER_CADDY}:{ca_internal_path}", dest_cert], stdout=subprocess.DEVNULL)
        
        current_user_proc = subprocess.run(["whoami"], capture_output=True, text=True)
        current_user = current_user_proc.stdout.strip() if current_user_proc.returncode == 0 else "root"
        subprocess.run(["sudo", "chown", f"{current_user}:{current_user}", dest_cert], stdout=subprocess.DEVNULL)
        

        print("\n\033[1;33m" + "="*70)
        print(" ACTION REQUIRED: HTTPS CERTIFICATE GENERATED")
        print("="*70)
        print(f" Your Unique DARDE Root CA has been saved to: \033[1;36m{dest_cert}\033[1;33m")
        print(" Run the automated Client Setup script on your end-user device.")
        print("="*70 + "\033[0m\n")


    else:
        print("[WARN] Could not locate Caddy root.crt inside the container.")
    
    configure_ufw()

def deploy_ai_stack(ram_limit_gb=4):
    """Deploys the Ollama backend and Open-WebUI frontend."""
    check_grc()
    print("\n[INFO] Deploying Level 2 AI Stack...")
    
    _run_podman(["rm", "-f", config.CONTAINER_WEBUI, config.CONTAINER_OLLAMA], ignore_errors=True)
    
    # FIX: Create the physical directory for the Ollama bind mount to bypass OverlayFS
    subprocess.run(["mkdir", "-p", config.OLLAMA_BIND_MOUNT], stdout=subprocess.DEVNULL)
    # Ensure the WebUI volume still exists as a standard volume
    _ensure_volume(config.VOL_WEBUI)

    print(f"[INFO] Starting AI Backend ({config.CONTAINER_OLLAMA})...")
    _run_podman([
        "run", "-d", "--restart=always", "--name", config.CONTAINER_OLLAMA,
        "--net=host",
        "-e", "OLLAMA_HOST=127.0.0.1:11434",
        "-e", "OLLAMA_KEEP_ALIVE=15m",
        # FIX: Replaced the old virtual volume with the direct bind mount path
        "-v", f"{config.OLLAMA_BIND_MOUNT}:/root/.ollama:Z",
        f"--memory={ram_limit_gb}g",
        f"--memory-swap={ram_limit_gb}g",
        "docker.io/ollama/ollama"
    ])

    print(f"[INFO] Starting AI Frontend ({config.CONTAINER_WEBUI})...")
    _run_podman([
        "run", "-d", "--restart=always", "--name", config.CONTAINER_WEBUI,
        "--net=host",
        "-e", "HOST=127.0.0.1",
        "-e", "PORT=8080",
        "-e", "OLLAMA_BASE_URL=http://127.0.0.1:11434",
        "-e", "FILE_UPLOAD_SIZE_LIMIT=5000",
        "-e", "ENABLE_RAG=False",
        "-v", f"{config.VOL_WEBUI}:/app/backend/data",
        "--memory=2g",
        "ghcr.io/open-webui/open-webui:main"
    ])
    
    wait_for_service_startup(8080)
    
    # Wait for the Ollama backend to become responsive before sending the pull command
    wait_for_service_startup(11434)
    
    configure_ufw()
    
    print("[INFO] Reloading proxy routing rules...")
    _run_podman(["exec", config.CONTAINER_CADDY, "caddy", "reload", "--config", "/etc/caddy/Caddyfile"], ignore_errors=True)
    print("[OK] Level 2 AI Stack successfully deployed.")

    print("\n[INFO] Initializing AI Model Configuration...")
    from ai.model_mgr import select_initial_model
    selected_model = select_initial_model()

    if selected_model and selected_model != "skip":
        print(f"\n[INFO] Pulling '{selected_model}' into Ollama. This will take several minutes...")
        
        # Added -t to force TTY allocation for rendering the Ollama progress bar
        _run_podman(["exec", "-t", config.CONTAINER_OLLAMA, "ollama", "pull", selected_model])
        
        print(f"\n[OK] Model '{selected_model}' is successfully installed and ready to use!")

        
def stop_all_containers():
    """Executes a hard stop on active project containers to flush RAM."""
    print("\n[INFO] Sending SIGTERM to all infrastructure containers...")
    targets = [
        config.CONTAINER_CADDY, 
        config.CONTAINER_ADGUARD, 
        config.CONTAINER_OLLAMA, 
        config.CONTAINER_WEBUI
    ]
    for target in targets:
        _run_podman(["stop", target], ignore_errors=True)
    print("[OK] All services halted. Resources freed.")