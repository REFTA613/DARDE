"""
DARDE - Authentication Module
Handles privilege escalation and maintains sudo token alive in the background.
(Resolves Sudo Password Prompts - Point 1)
"""

import subprocess
import threading
import time
import sys

class SudoKeeper:
    def __init__(self, interval=60):
        self.interval = interval
        self.running = False
        self._thread = None

    def _keep_alive_loop(self):
        """Background daemon loop that refreshes the sudo timestamp."""
        while self.running:
            try:
                # Silently refresh the sudo ticket without printing to stdout
                subprocess.run(
                    ["sudo", "-v"],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
            except subprocess.CalledProcessError:
                # If the refresh fails, it will attempt again on the next loop
                pass
            
            # Sleep in small chunks (1 sec) to allow immediate thread termination
            for _ in range(self.interval):
                if not self.running:
                    break
                time.sleep(1)

    def initialize(self):
        """Prompts user for sudo password once and spawns the background thread."""
        print("[INFO] Initializing administrative privileges for DARDE...")
        try:
            # Triggers the standard OS terminal password prompt
            subprocess.run(["sudo", "-v"], check=True)
        except subprocess.CalledProcessError:
            print("[FATAL] Administrative privileges (sudo) are strictly required. Exiting.")
            sys.exit(1)
        
        # Start background thread
        self.running = True
        self._thread = threading.Thread(target=self._keep_alive_loop, daemon=True)
        self._thread.start()
        print("[OK] Sudo token cached. Background keep-alive activated.")

    def stop(self):
        """Stops the background keep-alive thread cleanly on application exit."""
        self.running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2)
            
# Expose a singleton instance to be imported by main.py
sudo_manager = SudoKeeper()