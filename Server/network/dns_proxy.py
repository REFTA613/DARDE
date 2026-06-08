"""
DARDE - DNS and Proxy Configuration Module
Handles kernel routing, systemd-resolved masking, and reverse proxy definitions.
"""

import subprocess

import config

def _run_cmd(cmd_list):
    """
    Executes a shell command silently.
    """
    subprocess.run(cmd_list, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def configure_host_network():
    """
    Prepares the Arch/CachyOS host network.
    Disables NetworkManager DNS manipulation and masks systemd-resolved to free port 53.
    """
    print("\n[INFO] Configuring Kernel IP Forwarding and Host DNS...")
    
    # Enable IP Forwarding
    forward_conf = "net.ipv4.ip_forward=1\n"
    subprocess.run(f"echo '{forward_conf}' | sudo tee {config.SYSCTL_CONF_PATH} > /dev/null", shell=True)
    _run_cmd(["sudo", "sysctl", "-p", config.SYSCTL_CONF_PATH])

    # Disable systemd-resolved to prevent port 53 conflicts
    _run_cmd(["sudo", "systemctl", "disable", "--now", "systemd-resolved"])
    _run_cmd(["sudo", "systemctl", "mask", "systemd-resolved"])

    # Prevent NetworkManager from dynamically overwriting resolv.conf
    nm_conf = "[main]\ndns=none\n"
    subprocess.run("echo -e '" + nm_conf + "' | sudo tee /etc/NetworkManager/conf.d/99-dns-none.conf > /dev/null", shell=True)
    _run_cmd(["sudo", "systemctl", "reload", "NetworkManager"])

    # Force static bootstrap DNS to Cloudflare
    subprocess.run(f"sudo rm -f {config.RESOLV_CONF_PATH}", shell=True, stderr=subprocess.DEVNULL)
    subprocess.run(f"echo -e 'nameserver 1.1.1.1\nnameserver 1.0.0.1' | sudo tee {config.RESOLV_CONF_PATH} > /dev/null", shell=True)
    
    print("[OK] Host network routing and static DNS configured.")

def generate_caddyfile():
    """
    Generates the Caddyfile routing rules dynamically using variables from config.py.
    """
    print(f"[INFO] Generating Reverse Proxy routing rules...")
    
    _run_cmd(["sudo", "mkdir", "-p", config.CADDY_DIR])

    caddyfile_content = f"""{config.DOMAIN_DSP} {{
        tls internal
        reverse_proxy 127.0.0.1:9090
}}
{config.DOMAIN_AI} {{
        tls internal
        reverse_proxy 127.0.0.1:8080
}}
{config.DOMAIN_API} {{
        tls internal
        reverse_proxy 127.0.0.1:11434 {{
                header_up Host "localhost"
                header_up Origin "http://localhost"
        }}
}}
"""
    tmp_path = "/tmp/cai_caddyfile_tmp"
    with open(tmp_path, "w") as f:
        f.write(caddyfile_content)
    
    subprocess.run(["sudo", "mv", tmp_path, config.CADDYFILE_PATH], check=True)
    subprocess.run(["sudo", "chmod", "644", config.CADDYFILE_PATH], check=True)
    
    print(f"[OK] Caddyfile deployed at {config.CADDYFILE_PATH}.")

def deploy_network_config():
    """
    Execution wrapper for the network preparation phase.
    """
    configure_host_network()
    generate_caddyfile()