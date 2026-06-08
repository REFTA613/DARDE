"""
DARDE - Firewall and Network Audit Module
Verifies system ports (SSH, DNS, Proxy) and validates iptables routing rules.
"""

import subprocess
import re
import config

def _run_cmd(cmd):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, shell=isinstance(cmd, str))
    return result.stdout.strip()

def audit_firewall_and_ports():
    """
    Executes a comprehensive audit of listening ports and firewall rules.
    """
    print("\n" + "="*50)
    print("[ SYSTEM NETWORK & FIREWALL AUDIT ]")
    print("="*50)

    # 1. Port Scan via Socket Statistics (ss)
    print("\n[LISTENING PORTS]")
    ss_output = _run_cmd("ss -tuln")
    
    target_ports = {
        "22": "SSH Daemon",
        "53": "AdGuard DNS",
        "80": "HTTP Caddy",
        "443": "HTTPS Caddy",
        "3000": "AdGuard WebUI",
        "8080": "Open-WebUI",
        "11434": "Ollama API"
    }

    for port, service in target_ports.items():
        # Regex to match the exact port binding (e.g., :22 or 0.0.0.0:22)
        if re.search(r':' + port + r'\b', ss_output):
            print(f"  [\033[92mACTIVE\033[0m] Port {port:<5} - {service}")
        else:
            print(f"  [\033[91mCLOSED\033[0m] Port {port:<5} - {service}")

    # 2. Kernel IP Forwarding Check
    print("\n[ROUTING KERNEL]")
    ip_forward = _run_cmd("sysctl net.ipv4.ip_forward").split("=")[-1].strip()
    if ip_forward == "1":
        print("  [\033[92mACTIVE\033[0m] IPv4 Forwarding")
    else:
        print("  [\033[91mDISABLED\033[0m] IPv4 Forwarding")

    # 3. Geo-Block Iptables Check
    print("\n[FIREWALL RULES]")
    iptables_raw = _run_cmd("sudo iptables -t raw -L PREROUTING -n")
    if config.GEOBLOCK_IPSET_NAME in iptables_raw:
        print(f"  [\033[92mACTIVE\033[0m] IPSET Geo-Block ({config.GEOBLOCK_IPSET_NAME}) -> DROP")
    else:
        print(f"  [\033[93mINACTIVE\033[0m] IPSET Geo-Block not found in PREROUTING")

    print("\n" + "="*50)
    input("Press Enter to return to the main menu...")