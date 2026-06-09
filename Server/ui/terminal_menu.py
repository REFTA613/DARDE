"""
DARDE - Interactive UI Module
Manages the terminal-based menu navigation and user input logic.
"""

import sys
import os
import socket
import json

from config import TOPOLOGY_FILE, load_topology, save_topology, NODE_ROLE
from network.dns_proxy import deploy_network_config
from network.geoblock import update_geoblock_zones
from network.firewall import audit_firewall_and_ports
from core.container_mgr import deploy_adguard, deploy_caddy, deploy_ai_stack, stop_all_containers
from core.system_checks import run_all_checks
from ui.log_viewer import stream_logs
from core.watchdog import install_watchdog
from core.uninstaller import run_uninstall_sequence

try:
    import questionary
    from questionary import Style
except ImportError:
    print("[FATAL] 'questionary' library missing. Run the script via start.sh to bootstrap the environment.")
    sys.exit(1)

darde_theme = Style([
    ('qmark', 'fg:#00ffff bold'),
    ('question', 'fg:#ffffff bold'),
    ('pointer', 'fg:#00ffff bold'),
    ('highlighted', 'fg:#00ffff bold'),
    ('selected', 'fg:#00ff00'),
    ('separator', 'fg:#ff0000 bold'),
    ('instruction', 'fg:#888888 italic'),
    ('answer', 'fg:#ff0000 bold'),
])

def show_main_menu():
    """
    Displays the main interactive menu loop.
    """
    if not os.path.exists(TOPOLOGY_FILE):
        prompt_topology()

    while True:
        try:
            choice = questionary.select(
                "DARDE SERVER MANAGER",
                choices=[
                    "1. Install/Update Core (Caddy + AdGuard)",
                    "2. Install/Update AI Stack (Ollama + WebUI)",
                    "3. Update Security Geo-Block (RU, CN, IR)",
                    "4. Audit Firewall & Open Ports (SSH, DNS, Proxy)",
                    "5. Enable Auto-Heal Watchdog (Cron 9-min & Boot)",
                    "6. Diagnostics: Live Logs & Domain Status",
                    "7. Diagnostics: Run System Checks",
                    questionary.Separator("--- CRITICAL OPERATIONS ---"),
                    "8. Stop All Containers (Flush RAM)",
                    "9. UNINSTALL & RESTORE SYSTEM TO DEFAULT",
                    "0. Exit"
                ],
                instruction="(Press a number to jump instantly, then Enter to execute)",
                style=darde_theme,
                use_shortcuts=True
            ).ask()

            if choice is None or choice.startswith("0."):
                break

            if choice.startswith("1."):
                print("\n[ROUTING] Initializing Core Infrastructure deployment...")
                try:
                    deploy_network_config()
                    deploy_adguard()
                    deploy_caddy()
                    print("\n[\033[92mSUCCESS\033[0m] Core Infrastructure fully operational.")
                except Exception as e:
                    print(f"\n[\033[91mFATAL\033[0m] Core deployment failed: {e}")

            elif choice.startswith("2."):
                print("\n[ROUTING] Initializing AI Stack deployment...")
                try:
                    deploy_ai_stack()
                    print("\n[\033[92mSUCCESS\033[0m] AI Stack deployed successfully.")
                except Exception as e:
                    print(f"\n[\033[91mFATAL\033[0m] AI deployment failed: {e}")

            elif choice.startswith("3."):
                print("\n[ROUTING] Initializing Security Geo-Block update sequence...")
                try:
                    update_geoblock_zones()
                except Exception as e:
                    print(f"\n[\033[91mFATAL\033[0m] Geo-Block deployment failed: {e}")

            elif choice.startswith("4."):
                audit_firewall_and_ports()

            elif choice.startswith("5."):
                print("\n[ROUTING] Installing Cron job for auto-heal watchdog...")
                try:
                    install_watchdog()
                except Exception as e:
                    print(f"\n[\033[91mFATAL\033[0m] Watchdog installation failed: {e}")

            elif choice.startswith("6."):
                stream_logs()

            elif choice.startswith("7."):
                diag_choice = questionary.select(
                    "DIAGNOSTICS & DEBUG",
                    choices=[
                        "1. Run System Dependency Checks (Pre-Flight)",
                        "2. Live Infrastructure Dashboard (Real-Time Monitor)",
                        "3. Go Back"
                    ],
                    style=darde_theme
                ).ask()
                
                if diag_choice and diag_choice.startswith("1."):
                    print("\n[ROUTING] Forcing manual system diagnostics...")
                    run_all_checks()
                elif diag_choice and diag_choice.startswith("2."):
                    from core.system_checks import live_system_dashboard
                    live_system_dashboard()

            elif choice.startswith("8."):
                confirm_stop = questionary.confirm(
                    "CRITICAL: Are you sure you want to STOP ALL containers and interrupt the services?",
                    default=False,
                    style=darde_theme
                ).ask()
                
                if confirm_stop:
                    print("\n[ROUTING] Halting all running containers and flushing RAM...")
                    stop_all_containers()
                else:
                    print("\n[INFO] Operation aborted. Services are still running.")

            elif choice.startswith("9."):
                run_uninstall_sequence()

            print("\n" + "="*50 + "\n")

        except KeyboardInterrupt:
            break

def prompt_topology():
    print("\n\033[0;36m==========================================\033[0m")
    print("\033[1;36m  DARDE - TOPOLOGY INITIALIZATION WIZARD  \033[0m")
    print("\033[0;36m==========================================\033[0m\n")
    
    role = questionary.select(
        "Select the topological role for this physical server:",
        choices=[
            "1. [Standalone]  - All-in-One (Gateway + Security + Compute)",
            "2. [Gateway]     - Traffic Routing, Firewall & UI ONLY",
            "3. [Compute]     - AI Worker Node (Ollama LLM Backend ONLY)"
        ],
        style=darde_theme
    ).ask()
    
    role_map = {"1": "standalone", "2": "gateway", "3": "compute"}
    selected_role = role_map.get(role[0] if role else "1", "standalone")

    default_machine = socket.gethostname().lower().replace("-", "")
    
    machine_name = questionary.text(
        f"Enter physical Machine Name (e.g., 'server01', default: {default_machine}):",
        default=default_machine
    ).ask().strip().lower()

    node_name = questionary.text(
        "Enter logical Node Name (e.g., 'gateway1', 'compute-alpha'):",
        default="master"
    ).ask().strip().lower()

    compute_ip = "127.0.0.1"
    if selected_role == "gateway":
        print("\n\033[1;33m[!] Gateway Node Requires a Compute Node\033[0m")
        compute_ip = questionary.text(
            "Enter the LAN IP address of your DARDE Compute Node (e.g., 192.168.1.50):",
            default="192.168.1.50"
        ).ask().strip()

    save_topology(selected_role, node_name, machine_name, compute_ip)
    
    # =========================================================================
    # FIX A: Generazione automatica del profilo per la Smart Discovery dei Client
    # =========================================================================
    base_domain = f"{node_name}.{machine_name}.local"
    profile_data = {"base_domain": base_domain, "role": selected_role}
    home_dir = os.path.expanduser("~")
    profile_path = os.path.join(home_dir, "darde_client_profile.json")
    
    try:
        with open(profile_path, "w") as f:
            json.dump(profile_data, f, indent=2)
    except Exception as e:
        print(f"\n[WARN] Impossibile generare il profilo client JSON: {e}")

    print(f"\n\033[1;32m[OK] Topology saved! Base domain: {base_domain}\033[0m\n")
    return selected_role