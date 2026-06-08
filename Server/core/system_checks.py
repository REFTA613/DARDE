"""
DARDE - System Diagnostics Module
Verifies Arch Linux / CachyOS dependencies, Podman health, and provides Live Monitoring.
Uses modern Python 3 subprocess handling.
"""

import subprocess
import sys
import shutil
import time

try:
    import config
except ImportError:
    config = None

def check_dependencies():
    """
    Checks for required system packages via pacman with colored output.
    """
    print("\n\033[1;34m[INFO]\033[0m Running System Dependencies Check (Arch/CachyOS)...")
    
    required_pkgs = ["podman", "ipset", "iptables-nft", "cronie", "curl", "grc"]
    missing_pkgs = []

    for pkg in required_pkgs:
        result = subprocess.run(["pacman", "-Qs", f"^{pkg}$"], capture_output=True)
        if result.returncode != 0:
            missing_pkgs.append(pkg)

    if missing_pkgs:
        print(f"\033[1;33m[WARN]\033[0m Missing packages detected: {', '.join(missing_pkgs)}")
        print("\033[1;34m[INFO]\033[0m Starting automatic installation via pacman...")
        try:
            subprocess.run(["sudo", "pacman", "-Sy", "--needed", "--noconfirm"] + missing_pkgs, check=True)
            print("\033[1;32m[OK]\033[0m Packages installed successfully.")
        except subprocess.CalledProcessError:
            print("\033[1;31m[FATAL]\033[0m Failed to install required dependencies. Check internet connection.")
            sys.exit(1)
    else:
        print("\033[1;32m[OK]\033[0m All core dependencies are present.")

    cron_check = subprocess.run(["systemctl", "is-active", "--quiet", "cronie"], capture_output=True)
    if cron_check.returncode != 0:
        print("\033[1;34m[INFO]\033[0m Starting and enabling cronie service...")
        subprocess.run(["sudo", "systemctl", "enable", "--now", "cronie"], check=True)
        print("\033[1;32m[OK]\033[0m Cronie service active.")

def verify_podman_health():
    """
    Verifies the operational status of the Podman container engine with auto-heal.
    """
    print("\n\033[1;34m[INFO]\033[0m Running Podman Engine Health Check...")

    if not shutil.which("podman"):
        print("\033[1;31m[FATAL]\033[0m Podman binary is not found in PATH. Exiting.")
        sys.exit(1)

    engine_check = subprocess.run(["sudo", "podman", "info"], capture_output=True)

    if engine_check.returncode == 0:
        print("\033[1;32m[OK]\033[0m Podman engine is configured and responding correctly.")
        return

    print("\033[1;31m[ERROR]\033[0m Podman engine is installed but NOT responding.")
    print("\033[1;34m[INFO]\033[0m Attempting to auto-heal: loading kernel modules and resetting state...")
    
    subprocess.run(["sudo", "modprobe", "tun"], capture_output=True)
    subprocess.run(["sudo", "modprobe", "tap"], capture_output=True)
    subprocess.run(["sudo", "podman", "system", "reset", "--force"], capture_output=True)
    
    time.sleep(2)

    final_check = subprocess.run(["sudo", "podman", "info"], capture_output=True)

    if final_check.returncode != 0:
        print("\033[1;31m[FATAL]\033[0m Podman is completely broken. Check CachyOS kernel modules.")
        sys.exit(1)
    else:
        print("\033[1;32m[OK]\033[0m Podman auto-heal successful. Engine is now active.")

def run_all_checks():
    check_dependencies()
    verify_podman_health()
    print("\033[0;36m" + "-" * 50 + "\033[0m")

def live_system_dashboard():
    """
    Renders a real-time, colorized dashboard using modern subprocess standards.
    Shows Host RAM, Active GeoBlock rules, Live Dropped Packets, and Container Metrics.
    """
    print("\n\033[1;34m[INFO]\033[0m Initializing Live Telemetry... (Press Ctrl+C to exit)")
    time.sleep(1)
    
    try:
        while True:
            # 1. Fetch Host RAM (Modern subprocess.run)
            try:
                ram_cmd = "free -m | awk 'NR==2{printf \"%.1f%%\", $3*100/$2 }'"
                ram_proc = subprocess.run(ram_cmd, shell=True, capture_output=True, text=True)
                host_ram = ram_proc.stdout.strip() if ram_proc.returncode == 0 else "N/A"
            except Exception:
                host_ram = "N/A"
                
            # 2. Fetch GeoBlock count (Loaded Subnets)
            set_name = getattr(config, 'GEOBLOCK_IPSET_NAME', 'cai_geo_block') if config else 'cai_geo_block'
            try:
                ipset_cmd = f"sudo ipset list {set_name} | grep 'Number of entries' | awk '{{print $4}}'"
                ipset_proc = subprocess.run(ipset_cmd, shell=True, capture_output=True, text=True)
                ipset_count = ipset_proc.stdout.strip() if ipset_proc.returncode == 0 else "0"
            except Exception:
                ipset_count = "0"

            # 3. Fetch IPTables Live Drops (Packet Filter)
            try:
                iptables_cmd = f"sudo iptables -t raw -vL PREROUTING -n | grep {set_name}"
                iptables_proc = subprocess.run(iptables_cmd, shell=True, capture_output=True, text=True)
                iptables_out = iptables_proc.stdout.strip()
                
                if iptables_out and iptables_proc.returncode == 0:
                    parts = iptables_out.split()
                    pkts_dropped = parts[0]
                    bytes_dropped = parts[1]
                else:
                    pkts_dropped = "0"
                    bytes_dropped = "0B"
            except Exception:
                pkts_dropped = "0"
                bytes_dropped = "0B"

            # 4. Fetch Podman Stats (CPU/RAM)
            try:
                stats_proc = subprocess.run(
                    ["sudo", "podman", "stats", "--no-stream", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"],
                    capture_output=True, text=True
                )
                stats_output = stats_proc.stdout.strip()
            except Exception:
                stats_output = ""
                
            stats_map = {}
            if stats_output:
                for line in stats_output.split('\n'):
                    if '|' in line:
                        parts = line.split('|')
                        if len(parts) == 3:
                            stats_map[parts[0]] = {"cpu": parts[1], "mem": parts[2]}

            # 5. Fetch Podman Status
            try:
                ps_proc = subprocess.run(
                    ["sudo", "podman", "ps", "-a", "--format", "{{.Names}}|{{.State}}|{{.Status}}"],
                    capture_output=True, text=True
                )
                ps_output = ps_proc.stdout.strip()
            except Exception:
                ps_output = ""

            # --- RENDER DASHBOARD ---
            # Modern terminal wipe using ANSI escape code directly mapped to stdout, prevents scrolling history
            sys.stdout.write("\033c")
            sys.stdout.flush()

            print("\033[0;36m" + "═" * 70 + "\033[0m")
            print("\033[1;36m          DCS-CAI SERVER - LIVE DIAGNOSTICS DASHBOARD\033[0m")
            print("\033[0;36m" + "═" * 70 + "\033[0m")
            
            # Host Metrics
            print(f"  \033[1;37mHost RAM Usage:\033[0m      {host_ram}")
            
            # Firewall Telemetry
            geo_color = "\033[1;36m" if ipset_count.isdigit() and int(ipset_count) > 0 else "\033[1;33m"
            print(f"  \033[1;37mFirewall Memory:\033[0m     {geo_color}{ipset_count} Target Subnets Loaded\033[0m")
            
            if pkts_dropped == "0" or pkts_dropped == "":
                print(f"  \033[1;37mIPFilter Drops:\033[0m      \033[1;32m{pkts_dropped} Pkts ({bytes_dropped})\033[0m")
            else:
                print(f"  \033[1;37mIPFilter Drops:\033[0m      \033[1;31m{pkts_dropped} Pkts ({bytes_dropped})\033[0m  \033[1;31m[ACTIVE BLOCKS DETECTED]\033[0m")
            
            print("\033[0;36m" + "─" * 70 + "\033[0m")
            print("  \033[1;37mCONTAINER STATUS & LIVE RESOURCES\033[0m")
            print("\033[0;36m" + "─" * 70 + "\033[0m")

            targets = [
                getattr(config, 'CONTAINER_CADDY', 'cai-caddy') if config else 'cai-caddy',
                getattr(config, 'CONTAINER_ADGUARD', 'cai-adguard') if config else 'cai-adguard',
                getattr(config, 'CONTAINER_OLLAMA', 'cai-ollama') if config else 'cai-ollama',
                getattr(config, 'CONTAINER_WEBUI', 'cai-webui') if config else 'cai-webui',
                
            ]

            found_containers = []
            if ps_output:
                for line in ps_output.split('\n'):
                    if '|' in line:
                        parts = line.split('|')
                        if len(parts) >= 2:
                            name = parts[0]
                            state = parts[1]
                            if name in targets:
                                found_containers.append(name)
                                
                                if state.lower() == "running":
                                    color = "\033[0;32m"
                                    icon = "▶"
                                elif state.lower() == "exited":
                                    color = "\033[0;31m"
                                    icon = "■"
                                else:
                                    color = "\033[0;33m"
                                    icon = "⏸"
                                    
                                cpu = stats_map.get(name, {}).get("cpu", "0.00%")
                                mem = stats_map.get(name, {}).get("mem", "0B / 0B")
                                
                                print(f"  {color}{icon} {name.ljust(18)}\033[0m | {color}{state.upper().ljust(8)}\033[0m | CPU: {cpu.ljust(8)} | RAM: {mem}")

            missing = set(targets) - set(found_containers)
            for m in missing:
                print(f"  \033[0;90m■ {m.ljust(18)} | OFFLINE  | CPU: N/A       | RAM: N/A\033[0m")

            print("\033[0;36m" + "═" * 70 + "\033[0m")
            print("\033[0;90m  Updating every 2 seconds. Press Ctrl+C to exit.\033[0m")
            
            time.sleep(2)

    except KeyboardInterrupt:
        sys.stdout.write("\033c")
        sys.stdout.flush()
        print("\n\033[1;34m[INFO]\033[0m Exiting Live Diagnostics...")
        return