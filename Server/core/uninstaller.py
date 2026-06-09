"""
DARDE - System Uninstaller Module
Executes Soft and Bulldozer uninstall sequences with explicit debug logging.
"""

import subprocess
import sys
import time
import os

try:
    import config
except ImportError:
    config = None

try:
    import questionary
    from questionary import Style
    cai_theme = Style([
        ('qmark', 'fg:#00ffff bold'),
        ('question', 'fg:#ffffff bold'),
        ('pointer', 'fg:#00ffff bold'),
        ('highlighted', 'fg:#00ffff bold'),
        ('selected', 'fg:#00ff00'),
    ])
except ImportError:
    cai_theme = None

def _run(cmd, silent=False, ignore_errors=False):
    """
    Executes commands with a forced debug print to trace exact execution points.
    If ignore_errors is True, suppresses red ERROR/DETAILS blocks for expected failures.
    """
    cmd_str = cmd if isinstance(cmd, str) else ' '.join(cmd)
    print(f"\033[0;35m  [DEBUG] Executing: {cmd_str}\033[0m")
    
    try:
        if silent:
            result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, shell=isinstance(cmd, str), text=True)
        else:
            result = subprocess.run(cmd, stderr=subprocess.PIPE, shell=isinstance(cmd, str), text=True)
            
        if result.returncode != 0 and not ignore_errors:
            print(f"\033[0;31m  [ERROR] Command failed with exit code {result.returncode}\033[0m")
            if result.stderr:
                print(f"\033[0;31m  [DETAILS]: {result.stderr.strip()}\033[0m")
    except Exception as e:
        if not ignore_errors:
            print(f"\033[0;31m  [CRITICAL] Python failed to launch subprocess: {e}\033[0m")

def run_uninstall_sequence():
    print("\n\033[0;36m==========================================\033[0m")
    print("\033[0;36m       DARDE SERVER UNINSTALLER           \033[0m")
    print("\033[0;36m==========================================\033[0m\n")

    if cai_theme:
        choice = questionary.select(
            "How do you want to proceed with the infrastructure removal?",
            choices=[
                "1. SOFT UNINSTALL (Recommended for updates)",
                "2. BULLDOZER (Total Wipe & Cache Clear)",
                "3. CANCEL"
            ],
            style=cai_theme
        ).ask()
    else:
        print("1. SOFT UNINSTALL")
        print("2. BULLDOZER")
        print("3. CANCEL")
        choice = input("Make your choice (1/2/3): ")

    if choice is None or choice.startswith("3"):
        print("\n[INFO] Operation cancelled. No changes made.")
        return

    c_adguard = getattr(config, 'CONTAINER_ADGUARD', 'cai-adguard') if config else 'cai-adguard'
    c_caddy = getattr(config, 'CONTAINER_CADDY', 'cai-caddy') if config else 'cai-caddy'
    c_ollama = getattr(config, 'CONTAINER_OLLAMA', 'cai-ollama') if config else 'cai-ollama'
    c_webui = getattr(config, 'CONTAINER_WEBUI', 'cai-webui') if config else 'cai-webui'
    
    containers = [c_adguard, c_caddy, c_ollama, c_webui]

    # ==========================================
    # OPTION 1: SOFT UNINSTALL
    # ==========================================
    if choice.startswith("1"):
        print("\n\033[1;33m[INFO] Starting Soft Uninstall...\033[0m")
        print("[INFO] -> Removing containers...")
        for c in containers:
            _run(["sudo", "podman", "rm", "-f", c], ignore_errors=True)
            
        print("\n\033[0;32m[OK] Soft Uninstall complete. Data and volumes are safe.\033[0m\n")

    # ==========================================
    # OPTION 2: BULLDOZER
    # ==========================================
    elif choice.startswith("2"):
        if cai_theme:
            confirm = questionary.confirm(
                "WARNING: Point of no return. All data will be wiped. Proceed?",
                default=False,
                style=cai_theme
            ).ask()
        else:
            confirm = input("Proceed? (y/n): ").lower() == 'y'
            
        if not confirm:
            print("\n[INFO] Operation cancelled.")
            return

        print("\n\033[0;31m[WARN] Starting Bulldozer Uninstall. Point of no return.\033[0m")

        print("\n[INFO] -> 1/5 Destroying containers...")
        for c in containers:
            _run(["sudo", "podman", "rm", "-f", c], ignore_errors=True)

        print("\n[INFO] -> 2/5 Force wiping Podman volumes (AI Models, Database, Config)...")
        volumes = [
            getattr(config, 'VOL_ADGUARD_WORK', 'cai_adguard_work') if config else 'cai_adguard_work',
            getattr(config, 'VOL_ADGUARD_CONF', 'cai_adguard_conf') if config else 'cai_adguard_conf',
            getattr(config, 'VOL_CADDY_DATA', 'cai_caddy_data') if config else 'cai_caddy_data',
            getattr(config, 'VOL_CADDY_CONF', 'cai_caddy_config') if config else 'cai_caddy_config',
            getattr(config, 'VOL_OLLAMA', 'cai_ollama_storage') if config else 'cai_ollama_storage',
            getattr(config, 'VOL_WEBUI', 'cai_webui_storage') if config else 'cai_webui_storage'
        ]
        for v in volumes:
            _run(["sudo", "podman", "volume", "rm", "-f", v], ignore_errors=True)

        print("\n[INFO] -> 3/5 Removing Cached Images (Forcing fresh download)...")
        images = [
            "docker.io/adguard/adguardhome",
            "docker.io/library/caddy",
            "docker.io/ollama/ollama",
            "ghcr.io/open-webui/open-webui:main"
        ]
        for img in images:
            _run(["sudo", "podman", "rmi", "-f", img], ignore_errors=True)

        _run(["sudo", "podman", "image", "prune", "-f"], ignore_errors=True)

        print("\n[INFO] -> 4/5 Restoring native Host DNS routing and Network...")
        caddy_dir = getattr(config, 'CADDY_DIR', '/etc/caddy') if config else '/etc/caddy'
        _run(["sudo", "rm", "-rf", caddy_dir], silent=True, ignore_errors=True)
        _run(["sudo", "rm", "-f", "/etc/NetworkManager/conf.d/99-dns-none.conf"], silent=True, ignore_errors=True)
        _run(["sudo", "systemctl", "reload", "NetworkManager"], silent=True, ignore_errors=True)
        _run(["sudo", "systemctl", "unmask", "systemd-resolved"], silent=True, ignore_errors=True)
        _run(["sudo", "systemctl", "enable", "--now", "systemd-resolved"], silent=True, ignore_errors=True)
        _run(["sudo", "rm", "-f", "/etc/resolv.conf"], silent=True, ignore_errors=True)
        _run(["sudo", "ln", "-sf", "../run/systemd/resolve/stub-resolv.conf", "/etc/resolv.conf"], silent=True, ignore_errors=True)
        
        ipset_name = getattr(config, 'GEOBLOCK_IPSET_NAME', 'cai_geo_block') if config else 'cai_geo_block'
        
        _run(["sudo", "iptables", "-t", "raw", "-D", "PREROUTING", "-m", "set", "--match-set", ipset_name, "src", "-j", "DROP"], silent=True, ignore_errors=True)
        _run(["sudo", "ipset", "destroy", ipset_name], silent=True, ignore_errors=True)
        _run(["sudo", "rm", "-f", "/etc/cron.d/darde-watchdog"], silent=True, ignore_errors=True)
        _run(["sudo", "systemctl", "reload", "cronie"], silent=True, ignore_errors=True)

        print("\n[INFO] -> 5/5 Cleaning up local environment...")
        home_dir = os.path.expanduser("~")
        _run(f"rm -f {home_dir}/caddy-root*.crt {home_dir}/darde-root.crt {home_dir}/darde_client_profile.json", silent=True, ignore_errors=True)
        
        print("\n\033[0;32m[OK] System completely wiped. Cache cleared.\033[0m")
        print("\033[0;36m[DARDE] Uninstaller finished. Terminating environment...\033[0m")
        
        time.sleep(1)
        _run("sudo rm -rf .venv __pycache__", silent=True, ignore_errors=True)
        sys.exit(0)