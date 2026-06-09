#!/usr/bin/env python3
"""
DARDE - Main Orchestrator
Entry point for the deployment, watchdog daemon, system checks, and UI loop.
"""

import sys
from core.auth import sudo_manager
from core.system_checks import run_all_checks
from ui.terminal_menu import show_main_menu

# FIX: Import the missing modules for headless cron execution
from core.watchdog import run_diagnostics
from network.geoblock import update_geoblock_zones

def handle_headless_mode(args):
    """
    Intercepts command-line arguments for automated headless tasks (e.g., cron jobs).
    """
    if "--watchdog" in args:
        print("[INFO] Headless Watchdog Mode triggered.")
        # FIX: Replaced the 'TODO' with the actual execution function
        run_diagnostics()
        print("[OK] Watchdog sequence completed. Exiting.")
        sys.exit(0)

    # FIX: Added the missing listener for the nightly Geo-Block updates
    if "--update-geoblock" in args:
        print("[INFO] Headless Geo-Block Update triggered.")
        update_geoblock_zones(headless=True)
        print("[OK] Geo-Block sequence completed. Exiting.")
        sys.exit(0)

def main():
    """
    Main execution flow for interactive deployment.
    """
    # 1. Check for headless execution (cron / systemd daemon interactions)
    handle_headless_mode(sys.argv)
    
    # 2. Interactive Mode: Initialize Privilege Escalation
    try:
        sudo_manager.initialize()
    except Exception as e:
        print(f"[FATAL] Authentication failed: {e}")
        sys.exit(1)
        
    # 3. Execute System Pre-Flight Diagnostics (Pacman & Podman)
    run_all_checks()
        
    # 4. Launch Interactive UI Loop
    try:
        show_main_menu()
    except KeyboardInterrupt:
        # Fallback safety net if a Ctrl+C escapes the UI module
        print("\n[INFO] Emergency interrupt received at main level. Shutting down.")
    finally:
        # 5. Teardown: Safely kill the sudo daemon thread
        print("[INFO] Terminating background privilege daemon...")
        sudo_manager.stop()
        print("[OK] DARDE deployment tool closed cleanly.")
        sys.exit(0)

if __name__ == "__main__":
    main()