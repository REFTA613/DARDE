# DARDE — Dynamic AI Rapid Deployment Environment

DARDE is a **local-first infrastructure platform for deploying and managing AI services across multiple nodes on a private network**.

The project focuses on infrastructure automation, service isolation, secure internal communication and dynamic node configuration rather than on AI model development itself.

> AI infrastructure should be deployable and manageable as an infrastructure problem, not as a collection of manually configured machines.

**Project status: Work in Progress / Experimental**

---

## Overview

DARDE provides a deployment and orchestration layer for local AI services running on Linux and Windows clients.

A typical deployment can consist of:

```text
                    ┌─────────────────────┐
                    │       Client        │
                    │ Windows / Linux     │
                    └──────────┬──────────┘
                               │
                               │ HTTPS
                               ▼
                    ┌─────────────────────┐
                    │       Gateway       │
                    │                     │
                    │ Reverse Proxy       │
                    │ Service Routing     │
                    │ Web UI              │
                    └──────────┬──────────┘
                               │
                               │ HTTPS
                               ▼
                    ┌─────────────────────┐
                    │       Compute       │
                    │                     │
                    │ Ollama              │
                    │ AI inference        │
                    │ Internal proxy      │
                    └─────────────────────┘
```

The architecture is intended to keep AI inference and the service plane inside the local infrastructure where possible, without requiring an external cloud AI provider.

---

# Main goals

DARDE is being developed with the following goals:

- automated infrastructure deployment
- reproducible node configuration
- local AI inference
- separation between gateway and compute services
- encrypted communication between services
- reduced exposure of compute nodes
- automated network configuration
- security-oriented defaults
- support for multiple nodes on the same LAN
- minimal manual configuration for clients

The project is primarily an **infrastructure and systems engineering project**, not an AI application.

---

# Architecture

DARDE currently defines three main node roles.

## Standalone

A standalone node can provide the complete local stack:

- network configuration
- DNS handling
- firewall integration
- HTTPS termination
- Web UI
- Ollama
- AI services

This mode is useful for smaller deployments or testing.

---

## Gateway

The gateway acts as the entry point for clients.

Typical components include:

- Caddy reverse proxy
- Open WebUI
- optional AdGuard Home
- service routing
- HTTPS termination

The gateway is responsible for exposing services to trusted clients without directly exposing the compute layer.

---

## Compute

The compute node is intended to run the actual AI workloads.

Typical components include:

- Ollama
- AI models
- internal HTTPS proxy

The compute node is intentionally kept separate from the user-facing interface.

The goal is to minimize the number of services directly exposed by the machine running the models.

---

# Security model

Security is one of the main design considerations of DARDE.

The current implementation uses several layers of defense rather than relying on a single mechanism.

## Internal HTTPS

Internal services communicate through HTTPS using Caddy-managed certificates.

The project uses an internal CA for service certificates where appropriate.

This prevents sensitive requests and prompts from being transmitted as unencrypted HTTP traffic inside the infrastructure.

> Client certificate authentication / full mutual TLS is part of the planned security evolution and should not currently be considered a completed feature of the public repository.

---

## Network isolation

The architecture separates:

- clients
- gateway services
- compute services

This makes it possible to restrict which systems can directly communicate with the AI backend.

A compute node does not need to expose a public Web UI.

---

## Firewall integration

DARDE includes firewall inspection and network-security components intended to verify that the expected filtering rules and network configuration are active.

The system can inspect:

- listening ports
- IP forwarding
- firewall rules
- configured filtering mechanisms

---

## GeoIP filtering

DARDE can maintain GeoIP-based filtering rules using country-level IP ranges.

The current configuration includes:

```python
GEOBLOCK_COUNTRIES = ["ru", "cn", "ir"]
```

This feature is intended as **defense in depth**, not as a replacement for proper firewall configuration, authentication, patching or endpoint security.

GeoIP filtering can reduce unwanted network exposure, but it should never be treated as a complete security solution.

---

# Dynamic topology

DARDE is designed to support different node roles without requiring every machine to be manually configured.

The deployment process can configure services according to the selected role and network topology.

The long-term goal is to make adding a new compute node as simple as:

```text
Install → Configure → Authenticate → Join
```

rather than requiring manual configuration of every service and endpoint.

---

# Client provisioning

DARDE provides client setup scripts for:

- Linux
- Windows

The provisioning process is intended to automate tasks such as:

- installing required components
- configuring the client environment
- configuring service certificates
- configuring local name resolution
- preparing the environment for DARDE services

The goal is to make client onboarding reproducible and reduce configuration errors.

---

# Repository structure

```text
DARDE/
├── Client/
│   ├── setup_darde_client_linux.sh
│   ├── setup_darde_client_win.bat
│   └── setup_darde_client_win.ps1
│
├── Server/
│   ├── core/
│   │   ├── auth.py
│   │   ├── container_mgr.py
│   │   ├── system_checks.py
│   │   ├── uninstaller.py
│   │   └── watchdog.py
│   │
│   ├── network/
│   │   ├── dns_proxy.py
│   │   ├── firewall.py
│   │   └── geoblock.py
│   │
│   ├── config.py
│   └── main.py
│
├── docs/
└── README.md
```

---

# Installation

DARDE currently targets Linux-based server nodes.

The main entry point is:

```bash
python3 Server/main.py
```

The setup process performs system checks and configures the required infrastructure components.

The exact installation procedure is still evolving while the project is under active development.

---

# Design principles

DARDE follows a few principles.

### Local-first

AI inference should be capable of remaining inside the organization's own infrastructure.

### Explicit trust

Services should not automatically trust every machine simply because it is connected to the LAN.

### Minimal exposure

Services should expose only the interfaces required for their function.

### Automation over manual configuration

Infrastructure configuration should be reproducible and scriptable.

### Defense in depth

Security should be implemented through multiple independent layers rather than a single control.

### Infrastructure before application

The project treats AI deployment primarily as an infrastructure, networking and systems-engineering problem.

---

# Current status

DARDE is **experimental software under active development**.

The current repository contains working components for:

- node configuration
- service orchestration
- container management
- HTTPS proxy configuration
- network inspection
- firewall integration
- GeoIP filtering
- client provisioning
- system checks
- watchdog functionality

Some security and infrastructure components are still being refined.

The public repository should therefore be considered a **development project and technical prototype**, not a production-certified security platform.

---

# Roadmap

Planned improvements include:

- [ ] mutual TLS / client certificate authentication
- [ ] certificate lifecycle management
- [ ] certificate rotation and revocation
- [ ] stronger service identity verification
- [ ] improved privilege separation
- [ ] reduction of long-lived privileged processes
- [ ] automated firewall validation
- [ ] improved logging and monitoring
- [ ] automated multi-node testing
- [ ] better failure recovery
- [ ] configuration validation
- [ ] deployment rollback
- [ ] expanded documentation
- [ ] security testing and hardening

---

# Why DARDE?

Running local AI systems often becomes complicated once multiple machines are involved.

A single workstation running Ollama is relatively simple.

A real infrastructure introduces additional problems:

- How do clients discover the AI service?
- How is traffic routed?
- How are certificates distributed?
- How are compute nodes isolated?
- How are machines added or removed?
- How are configuration errors detected?
- How can the infrastructure be reproduced?
- How can the attack surface be reduced?

DARDE is an attempt to solve these problems at the infrastructure layer.

---

# Technology

DARDE currently uses technologies including:

- Linux
- Python
- Bash
- PowerShell
- Docker
- Caddy
- Ollama
- Open WebUI
- iptables
- GeoIP/IPSet-based filtering
- HTTPS/TLS

The project intentionally relies on established infrastructure components rather than implementing its own networking stack.

---

# Disclaimer

DARDE is a personal research and development project.

It should not currently be considered a hardened enterprise security product.

Security mechanisms should be independently reviewed and tested before deploying DARDE in environments containing sensitive or production-critical workloads.

---

## Project status

**Development / Experimental**

The architecture is evolving as new infrastructure, networking and security requirements are tested.

The primary objective is to build a practical, reproducible and security-conscious platform for local AI infrastructure.
