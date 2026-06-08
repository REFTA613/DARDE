"""
DARDE - Auto-Heal Watchdog Module
Registers system-level cron jobs to guarantee infrastructure uptime
and automatically update security firewalls.
"""

import os
import subprocess
import config

def install_watchdog():
    """
    Deploys a cron file in /etc/cron.d/ to trigger headless diagnostics.
    Runs at system boot, every 9 minutes for health checks, and at midnight for Geo-Block updates.
    """
    cron_file = "/etc/cron.d/dcs-cai-watchdog"
    
    # Calculate absolute paths to ensure cron executes correctly regardless of environment
    python_bin = os.path.join(config.PROJECT_ROOT, ".venv", "bin", "python")
    main_script = os.path.join(config.PROJECT_ROOT, "main.py")
    
    log_file_health = "/var/log/dcs-cai-watchdog.log"
    log_file_geoblock = "/var/log/dcs-cai-geoblock-update.log"

    print("\n[INFO] Generating Watchdog cron directives...")

    cron_content = f"""# DARDE Auto-Heal & Maintenance Daemon
# Executed strictly as root to manipulate podman and iptables states.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 1. Boot check: ensure infrastructure starts up cleanly
@reboot root {python_bin} {main_script} --watchdog >> {log_file_health} 2>&1

# 2. Pulse check: verify container health every 9 minutes
*/9 * * * * root {python_bin} {main_script} --watchdog >> {log_file_health} 2>&1

# 3. Nightly Maintenance: silently update Geo-Block IPs at 00:00 (Midnight)
0 0 * * * root {python_bin} {main_script} --update-geoblock >> {log_file_geoblock} 2>&1
"""
    
    tmp_path = "/tmp/cai_watchdog_cron"
    with open(tmp_path, "w") as f:
        f.write(cron_content)
    
    subprocess.run(["sudo", "mv", tmp_path, cron_file], check=True)
    subprocess.run(["sudo", "chmod", "644", cron_file], check=True)
    subprocess.run(["sudo", "chown", "root:root", cron_file], check=True)
    
    # Reload cron daemon to apply the new file immediately
    subprocess.run(["sudo", "systemctl", "reload", "cronie"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    print(f"[OK] Watchdog installed successfully at {cron_file}.")
    print("[INFO] System will auto-heal infrastructure continuously.")
    print("[INFO] Geo-Block lists will automatically refresh every night at 00:00.")

def run_diagnostics():
    """
    Execution logic for the headless auto-heal mode. Restarts stopped containers.
    """
    # This logic maps to Option 7. It imports system_checks to run silently.
    from core.system_checks import run_all_checks
    run_all_checks()
    
    # Extract dynamic container names safely
    targets = [
        getattr(config, 'CONTAINER_ADGUARD', 'cai-adguard'),
        getattr(config, 'CONTAINER_CADDY', 'cai-caddy'),
        getattr(config, 'CONTAINER_OLLAMA', 'cai-ollama'),
        getattr(config, 'CONTAINER_WEBUI', 'cai-webui'),

    ]
    
    for container in targets:
        result = subprocess.run(
            ["sudo", "podman", "container", "inspect", "-f", "{{.State.Status}}", container],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        status = result.stdout.strip()
        
        # If not running (and exists), force start it
        if status != "running" and status != "":
            subprocess.run(["sudo", "podman", "start", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)