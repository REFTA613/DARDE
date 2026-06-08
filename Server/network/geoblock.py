"""
DARDE - Security Geo-Blocking Module
Downloads regional IPv4 CIDR blocks and injects them directly into Kernel RAM via ipset.
Features interactive selection of custom countries or predefined geopolitical threat axes.
"""

import subprocess

import urllib.request

import config

try:
    import questionary
    from questionary import Style
    cai_theme = Style([
        ('qmark', 'fg:#00ffff bold'),
        ('question', 'fg:#ffffff bold'),
        ('pointer', 'fg:#00ffff bold'),
        ('highlighted', 'fg:#00ffff bold'),
        ('selected', 'fg:#00ff00'),
        ('instruction', 'fg:#888888 italic'),
        ('answer', 'fg:#ff0000 bold')
    ])
except ImportError:
    cai_theme = None

def _run_cmd(cmd_list, ignore_errors=False):
    """Executes a shell command silently."""
    result = subprocess.run(cmd_list, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not ignore_errors and result.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd_list)}")

def fetch_zones(country_codes):
    """
    Downloads IPv4 CIDR blocks for the specified ISO country codes.
    Merges all IPs into a single temporary list.
    """
    merged_ips = []
    print(f"\n[INFO] Downloading routing rules for: {', '.join(country_codes).upper()}...")

    for code in country_codes:
        url = f"https://www.ipdeny.com/ipblocks/data/countries/{code}.zone"
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as response:
                content = response.read().decode('utf-8').splitlines()
                merged_ips.extend(content)
                print(f"  -> [{code.upper()}] Fetched {len(content)} subnets.")
        except Exception as e:
            print(f"  -> [\033[91mFAIL\033[0m] Could not download data for {code.upper()}: {e}")

    return merged_ips

def inject_to_kernel(ips):
    """
    Compresses the IP list into a Kernel Hash Table using ipset,
    then applies the PREROUTING drop rule via iptables.
    """
    if not ips:
        print("\n[WARN] No IPs downloaded. Aborting Kernel injection.")
        return

    print(f"\n[INFO] Compressing {len(ips)} subnets into Kernel RAM (ipset)...")
    
    # Define ipset name from config or use default
    set_name = getattr(config, 'GEOBLOCK_IPSET_NAME', 'cai_geo_block')
    
    # 1. Clean existing rules
    _run_cmd(["sudo", "iptables", "-t", "raw", "-D", "PREROUTING", "-m", "set", "--match-set", set_name, "src", "-j", "DROP"], ignore_errors=True)
    _run_cmd(["sudo", "ipset", "destroy", set_name], ignore_errors=True)
    
    # 2. Create optimized hash table
    # maxelem is dynamically calculated to fit all downloaded IPs safely (x2 for safety margin)
    max_elem = max(65536, len(ips) * 2)
    _run_cmd(["sudo", "ipset", "create", set_name, "hash:net", "maxelem", str(max_elem)])
    
    # 3. Fast injection via ipset restore
    print("[INFO] Executing high-speed memory injection...")
    restore_content = ""
    for ip in ips:
        restore_content += f"add {set_name} {ip}\n"
        
    process = subprocess.Popen(["sudo", "ipset", "restore"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True)
    process.communicate(input=restore_content)
    
    # 4. Activate the silent DROP rule
    print("[INFO] Activating stealth DROP rule in iptables PREROUTING chain...")
    _run_cmd(["sudo", "iptables", "-t", "raw", "-I", "PREROUTING", "-m", "set", "--match-set", set_name, "src", "-j", "DROP"])
    
    print("\n\033[0;32m[OK] Geo-Block successfully activated. Target zones are now blind to this server.\033[0m")

def _get_headless_targets():
    """Returns default targets for automated cron updates."""
    # Default to the primary hostile axis if triggered by Watchdog
    return ['ru', 'cn', 'ir', 'kp', 'sy', 'by']

def update_geoblock_zones(headless=False):
    """
    Main function. Presents an interactive menu to the user or processes default targets silently.
    """
    if headless:
        targets = _get_headless_targets()
        ips = fetch_zones(targets)
        inject_to_kernel(ips)
        return

    print("\n\033[0;36m==========================================\033[0m")
    print("\033[0;36m     DCS-CAI GEO-POLITICAL FIREWALL       \033[0m")
    print("\033[0;36m==========================================\033[0m\n")

    if not cai_theme:
        print("[FATAL] Questionary library missing. Using default headless targets.")
        targets = _get_headless_targets()
        ips = fetch_zones(targets)
        inject_to_kernel(ips)
        return

    # Define Pre-Packaged Threat Axes
    axis_1 = ['ru', 'cn', 'ir', 'kp', 'sy', 'by'] # The comprehensive hostile axis
    axis_2 = ['ru', 'by'] # Eastern Europe conflict zone
    axis_3 = ['cn', 'kp'] # Asia-Pacific hostile zone
    axis_4 = ['ir', 'sy', 'iq', 'lb', 'ye'] # Middle East hostile zone

    choice = questionary.select(
        "Select the geopolitical threat profile to block:",
        choices=[
            "1. ENTIRE HOSTILE AXIS (Russia, China, Iran, N.Korea, Syria, Belarus)",
            "2. Eastern Europe Conflict Zone (Russia, Belarus)",
            "3. Asia-Pacific Threat Zone (China, N.Korea)",
            "4. Middle East Threat Zone (Iran, Syria, Iraq, Lebanon, Yemen)",
            questionary.Separator("--- MANUAL CONTROL ---"),
            "5. Custom Selection (Enter ISO Codes manually)",
            "6. DISABLE FIREWALL (Flush memory and allow all)",
            "0. Cancel"
        ],
        style=cai_theme
    ).ask()

    if choice is None or choice.startswith("0"):
        print("\n[INFO] Operation cancelled. Firewall state unchanged.")
        return

    targets = []

    if choice.startswith("1"):
        targets = axis_1
    elif choice.startswith("2"):
        targets = axis_2
    elif choice.startswith("3"):
        targets = axis_3
    elif choice.startswith("4"):
        targets = axis_4
    
    elif choice.startswith("5"):
        # Custom Manual Input
        custom_input = questionary.text(
            "Enter 2-letter ISO country codes separated by space (e.g. 'ru cn in br'):",
            style=cai_theme
        ).ask()
        
        if custom_input:
            # Clean input: lowercase, split by space, remove empty strings, keep only 2-char codes
            targets = [code.lower().strip() for code in custom_input.split() if len(code.strip()) == 2]
            
        if not targets:
            print("\n[WARN] Invalid input. Operation cancelled.")
            return

    elif choice.startswith("6"):
        # Disable Firewall Sequence
        print("\n[WARN] Flushing Geo-Block rules and neutralizing Firewall...")
        set_name = getattr(config, 'GEOBLOCK_IPSET_NAME', 'cai_geo_block')
        _run_cmd(["sudo", "iptables", "-t", "raw", "-D", "PREROUTING", "-m", "set", "--match-set", set_name, "src", "-j", "DROP"], ignore_errors=True)
        _run_cmd(["sudo", "ipset", "destroy", set_name], ignore_errors=True)
        print("\033[0;32m[OK] Firewall neutralized. Server is open to all regions.\033[0m")
        return

    # Execute Download and Injection
    ips = fetch_zones(targets)
    if ips:
        inject_to_kernel(ips)