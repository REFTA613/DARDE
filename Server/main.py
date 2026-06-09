#!/usr/bin/env python3
"""
DCS-CAI-SERVER - Main Orchestrator
Entry point for the deployment, watchdog daemon, system checks, and UI loop.
"""

import sys
import traceback
from core.auth import sudo_manager
from core.system_checks import run_all_checks
from ui.terminal_menu import show_main_menu
from core.watchdog import run_diagnostics
from network.geoblock import update_geoblock_zones

def handle_headless_mode(args):
    """
    Intercepts command-line arguments for automated headless tasks (e.g., cron jobs).
    """
    if "--watchdog" in args:
        print("[INFO] Headless Watchdog Mode triggered.")
        run_diagnostics()
        print("[OK] Watchdog sequence completed. Exiting.")
        sys.exit(0)

    if "--update-geoblock" in args:
        print("[INFO] Headless Geo-Block Update triggered.")
        update_geoblock_zones(headless=True)
        print("[OK] Geo-Block sequence completed. Exiting.")
        sys.exit(0)

def main():
    """
    Main execution flow for interactive deployment.
    """
    handle_headless_mode(sys.argv)
    
    try:
        sudo_manager.initialize()
    except Exception as e:
        print(f"[FATAL] Authentication failed: {e}")
        sys.exit(1)
        
    run_all_checks()
        
    exit_code = 0
    try:
        show_main_menu()
    except KeyboardInterrupt:
        print("\n[INFO] Emergency interrupt received at main level. Shutting down.")
    except Exception as e:
        # Prevents silent crashes by exposing the raw traceback directly to the terminal
        print(f"\n\033[0;31m[FATAL] Unhandled system crash: {e}\033[0m")
        traceback.print_exc()
        exit_code = 1
    finally:
        print("[INFO] Terminating background privilege daemon...")
        sudo_manager.stop()
        print("[OK] DCS-CAI-SERVER deployment tool closed cleanly.")
        sys.exit(exit_code)

if __name__ == "__main__":
    main()