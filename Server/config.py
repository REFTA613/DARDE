"""
DARDE - Configuration Module
Centralized configuration for naming conventions, domains, and global settings.
"""

import os
import json
import socket

# --- BASE DEFINITIONS ---
SYS_PREFIX = "darde"
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))

# --- TOPOLOGY STATE (Dynamic Domain Generation) ---
TOPOLOGY_FILE = os.path.join(PROJECT_ROOT, "topology.json")

def load_topology():
    if os.path.exists(TOPOLOGY_FILE):
        with open(TOPOLOGY_FILE, "r") as f: 
            return json.load(f)
    return {}

def save_topology(role, node_name, machine_name, compute_ip="127.0.0.1"):
    data = {
        "role": role, 
        "node_name": node_name, 
        "machine_name": machine_name,
        "compute_ip": compute_ip
    }
    with open(TOPOLOGY_FILE, "w") as f: 
        json.dump(data, f, indent=2)

_topo = load_topology()
MACHINE_NAME = _topo.get("machine_name", socket.gethostname().lower().replace("-", ""))
COMPUTE_NODE_IP = _topo.get("compute_ip", "127.0.0.1")
NODE_ROLE = _topo.get("role", "standalone")
NODE_NAME = _topo.get("node_name", "master")
MACHINE_NAME = _topo.get("machine_name", socket.gethostname().lower().replace("-", ""))

# Generates domains like: master.server01.local
DOMAIN_SUFFIX = f"{NODE_NAME}.{MACHINE_NAME}.local"

# --- DOMAIN NAMES ---
DOMAIN_DSP = f"dsp.{DOMAIN_SUFFIX}"
DOMAIN_AI = f"ai.{DOMAIN_SUFFIX}"
DOMAIN_API = f"api.{DOMAIN_SUFFIX}"

# --- CONTAINER NAMES ---
CONTAINER_ADGUARD = f"{SYS_PREFIX}-adguard"
CONTAINER_CADDY = f"{SYS_PREFIX}-caddy"
CONTAINER_OLLAMA = f"{SYS_PREFIX}-ollama"
CONTAINER_WEBUI = f"{SYS_PREFIX}-webui"
CONTAINER_TEMP_OLLAMA = f"{SYS_PREFIX}-temp-ollama"

# --- PODMAN VOLUMES & BIND MOUNTS ---
VOL_ADGUARD_WORK = f"{SYS_PREFIX}_adguard_work"
VOL_ADGUARD_CONF = f"{SYS_PREFIX}_adguard_conf"
VOL_CADDY_DATA = f"{SYS_PREFIX}_caddy_data"
VOL_CADDY_CONF = f"{SYS_PREFIX}_caddy_config"
VOL_WEBUI = f"{SYS_PREFIX}_webui_storage"

# Hardened bind mount for LLM storage to bypass OverlayFS limits
OLLAMA_BIND_MOUNT = os.path.expanduser("~/.ollama_storage")

# --- SECURITY ZONES ---
GEOBLOCK_COUNTRIES = ["ru", "cn", "ir"]
GEOBLOCK_IPSET_NAME = f"{SYS_PREFIX}_geo_block"

# --- SYSTEM PATHS ---
RESOLV_CONF_PATH = "/etc/resolv.conf"
SYSCTL_CONF_PATH = "/etc/sysctl.d/30-ipforward.conf"
CADDY_DIR = "/etc/caddy"
CADDYFILE_PATH = f"{CADDY_DIR}/Caddyfile"

# --- COMPUTE NODE SETTINGS ---
COMPUTE_API_PORT = 8443
CONTAINER_MICRO_PROXY = f"{SYS_PREFIX}-micro-proxy"