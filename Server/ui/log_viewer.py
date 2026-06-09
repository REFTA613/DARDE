"""
DARDE - Live Log Viewer & Domain Status
Provides the Domain Dashboard and streams Podman logs piped natively through GRC.
"""

import subprocess

import config

try:
    import questionary
    from questionary import Style
except ImportError:
    pass

cai_theme = Style([
    ('qmark', 'fg:#00ffff bold'),
    ('question', 'fg:#ffffff bold'),
    ('pointer', 'fg:#00ffff bold'),
    ('highlighted', 'fg:#00ffff bold'),
    ('selected', 'fg:#00ff00'),
])

def _generate_grc_config():
    """
    Generates a temporary configuration file for grcat using Python Raw Strings 
    to ensure perfect regex parsing by the GRC engine.
    """
    conf_path = "/tmp/cai_grcat.conf"
    
    # Raw string prevents Python from escaping backslashes improperly
    grc_rules = r"""
# Timestamps and Dates
regexp=\d{4}[-/]\d{2}[-/]\d{2}[T ]\d{2}:\d{2}:\d{2}[Z\+\-\d\.]*
colours=dark white
count=more
======
# IP Addresses
regexp=\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b
colours=cyan
count=more
======
# Errors / Fatal
regexp=(?i)(ERROR|FATAL|DENIED|PANIC|ERR|FAIL)
colours=red
count=more
======
# Warnings
regexp=(?i)(WARN|WARNING)
colours=yellow
count=more
======
# Info / Success
regexp=(?i)(INFO|SUCCESS|READY|OK)
colours=green
count=more
======
# HTTP Methods
regexp=\b(GET|POST|PUT|DELETE|PATCH)\b
colours=magenta
count=more
======
# HTTP Status 2xx/3xx
regexp=\s(20[0-9]|30[0-9])\s
colours=green
count=more
======
# HTTP Status 4xx/5xx
regexp=\s(40[0-9]|50[0-9])\s
colours=red
count=more
"""
    # Write cleanly to file
    with open(conf_path, "w") as f:
        f.write(grc_rules.strip() + "\n")
    
    return conf_path

def show_domain_status():
    """
    Displays the configured domain names and their internal routing targets.
    """
    import os
    
    # Recupera il nome esatto del sistema operativo leggendo i file di sistema Linux
    os_name = "Linux"
    if os.path.exists("/etc/os-release"):
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    os_name = line.split("=")[1].strip().strip('"')
                    break

    print("\n" + "="*50)
    print("[ ACTIVE DOMAIN ROUTING MAP ]")
    print("="*50)
    # Stampa in giallo l'OS e il Base Domain per farli risaltare
    print(f"  \033[1;33mHost OS:\033[0m     {os_name}")
    print(f"  \033[1;33mBase Domain:\033[0m {config.DOMAIN_SUFFIX}")
    print("-" * 50)
    print(f"  \033[96m{config.DOMAIN_DSP}\033[0m -> 127.0.0.1:9090 (Reserved)")
    print(f"  \033[96m{config.DOMAIN_AI}\033[0m  -> 127.0.0.1:8080 (Frontend WebUI)")
    print(f"  \033[96m{config.DOMAIN_API}\033[0m -> 127.0.0.1:11434 (Backend Ollama)")
    print("="*50 + "\n")

def stream_logs():
    """
    Displays domain status, opens sub-menu, and securely pipes logs to grcat.
    """
    show_domain_status()

    target_map = {
        "1": config.CONTAINER_CADDY,
        "2": config.CONTAINER_ADGUARD,
        "3": config.CONTAINER_OLLAMA,
        "4": config.CONTAINER_WEBUI
    }

    choices = [
        f"1. Proxy / Routing ({config.CONTAINER_CADDY})",
        f"2. Security DNS ({config.CONTAINER_ADGUARD})",
        f"3. AI Backend ({config.CONTAINER_OLLAMA})",
        f"4. AI Frontend ({config.CONTAINER_WEBUI})",
        "5. Go Back"
    ]

    choice = questionary.select(
        "Select container to monitor:",
        choices=choices,
        style=cai_theme,
        use_shortcuts=True
    ).ask()

    if choice is None or choice.startswith("5."):
        return

    selected_key = choice.split(".")[0]
    container_name = target_map[selected_key]
    grc_conf = _generate_grc_config()

    print(f"\n[INFO] Connecting to {container_name} log stream... (Press Ctrl+C to exit)")
    print("=" * 70)

    try:
        # Popen 1: Grab Podman logs
        podman_proc = subprocess.Popen(
            ["sudo", "podman", "logs", "-f", "--tail", "50", container_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        
        # Popen 2: Pipe the stream into grcat
        grc_proc = subprocess.Popen(
            ["grcat", grc_conf],
            stdin=podman_proc.stdout
        )
        
        podman_proc.stdout.close()
        grc_proc.communicate()

    except KeyboardInterrupt:
        pass
    finally:
        if 'grc_proc' in locals() and grc_proc.poll() is None:
            grc_proc.terminate()
        if 'podman_proc' in locals() and podman_proc.poll() is None:
            podman_proc.terminate()
            
        print("\n" + "=" * 70)
        print("[INFO] Detached from log stream.")