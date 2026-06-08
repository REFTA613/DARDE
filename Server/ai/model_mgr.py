"""
DARDE - AI Model Manager
Handles hardware analysis and intelligent model selection with tiered categories.
"""


try:
    import questionary
    from questionary import Choice, Separator, Style
except ImportError:
    print("[ERROR] questionary module missing. Run: pip install questionary")
    exit(1)

# Custom theme to fix the rendering and make the interface sharp and clear
cai_model_theme = Style([
    ('separator', 'fg:#00ffff bold'),
    ('pointer', 'fg:#00ffff bold'),
    ('highlighted', 'fg:#ffffff bold'),
    ('selected', 'fg:#00ff00 bold'),
    ('ideal', 'fg:#00ff00 bold'),
    ('marginal', 'fg:#ffff00 bold'),
    ('no', 'fg:#ff0000 bold'),
    ('desc', 'fg:#8a8a8a'),
    ('disabled', 'fg:#585858 italic'),
])

def get_system_ram_gb():
    """Reads total physical system RAM in Gigabytes."""
    try:
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if 'memtotal' in line.lower():
                    return round(int(line.split()[1]) / (1024 * 1024), 1)
    except Exception:
        pass
    
    return 8.0

def _build_choice(model_name, req, desc, system_ram):
    """Formats the choice using native questionary token styling for perfect alignment."""
    if system_ram >= (req * 1.5):
        status_tag = "● [IDEAL]"
        status_class = "class:ideal"
        is_disabled = False
    elif system_ram >= (req * 0.9):
        status_tag = "▲ [MARGINAL]"
        status_class = "class:marginal"
        is_disabled = False
    else:
        status_tag = "■ [NO]"
        status_class = "class:no"
        is_disabled = "Insufficient RAM"

    # Precise column padding for clean layout alignment
    padded_tag = status_tag.ljust(13)
    padded_name = model_name.ljust(20)
    padded_req = f"(Req: {str(req).rjust(4)}GB)".ljust(13)

    if is_disabled:
        title_tokens = [
            (status_class, padded_tag),
            ('class:disabled', f" {padded_name} {padded_req} - Insufficient RAM")
        ]
    else:
        title_tokens = [
            (status_class, padded_tag),
            ('', f" {padded_name} {padded_req} "),
            ('class:desc', f"- {desc}")
        ]

    return Choice(title=title_tokens, value=model_name, disabled=is_disabled)

def select_initial_model():
    """Displays a beautifully formatted, structured TUI menu for model selection."""
    system_ram = get_system_ram_gb()
    print(f"\n\033[0;36m[AUDIT] Hardware Analysis: {system_ram} GB of System RAM detected.\033[0m\n")

    choices = []

    # --- LLAMA FAMILY ---
    choices.append(Separator("=== LLAMA 3 FAMILY (General Reasoning) ==="))
    choices.append(_build_choice("llama3.2:3b", 4.0, "[LOW]  3B  - Fast and lightweight", system_ram))
    choices.append(_build_choice("llama3.1:8b", 8.0, "[MID]  8B  - The Meta standard, great balance", system_ram))
    choices.append(_build_choice("llama3.1:70b", 64.0, "[HIGH] 70B - Enterprise-grade logic", system_ram))

    # --- DEEPSEEK FAMILY ---
    choices.append(Separator("=== DEEPSEEK FAMILY (Advanced Logic & Code) ==="))
    choices.append(_build_choice("deepseek-r1:1.5b", 4.0, "[LOW]  1.5B - Lightning fast reasoning", system_ram))
    choices.append(_build_choice("deepseek-r1:8b", 8.0, "[MID]  8B   - Excellent logic and math", system_ram))
    choices.append(_build_choice("deepseek-r1:32b", 32.0, "[HIGH] 32B  - Top-tier reasoning capabilities", system_ram))

    # --- QWEN CODER FAMILY ---
    choices.append(Separator("=== QWEN 2.5 FAMILY (Coding & Dev) ==="))
    choices.append(_build_choice("qwen2.5-coder:3b", 4.0, "[LOW]  3B  - Quick script assistant", system_ram))
    choices.append(_build_choice("qwen2.5-coder:7b", 8.0, "[MID]  7B  - Solid coding companion", system_ram))
    choices.append(_build_choice("qwen2.5-coder:14b", 14.0, "[MID+] 14B - Heavyweight coding specialist", system_ram))
    choices.append(_build_choice("qwen2.5-coder:32b", 32.0, "[HIGH] 32B - Advanced software architect", system_ram))

    # --- MISTRAL FAMILY ---
    choices.append(Separator("=== MISTRAL FAMILY (Flexible & Context) ==="))
    choices.append(_build_choice("phi3:mini", 4.0, "[LOW]  3.8B - Microsoft edge model", system_ram))
    choices.append(_build_choice("mistral:7b", 8.0, "[MID]  7B   - Highly solid on logic tasks", system_ram))
    choices.append(_build_choice("mixtral:8x7b", 32.0, "[HIGH] 47B  - MoE powerful infrastructure", system_ram))

    # --- UTILITIES ---
    choices.append(Separator("=== UTILITIES ==="))
    choices.append(Choice(title=[('', "Enter a custom Ollama model tag manually (Advanced)")], value="custom"))
    choices.append(Choice(title=[('class:desc', "Skip model installation for now")], value="skip"))

    print("Select the base AI model to download and install in Ollama:")
    selected_model = questionary.select(
        "",
        choices=choices,
        style=cai_model_theme,
        use_indicator=True
    ).ask()

    if selected_model == "custom":
        print("\n\033[0;33m[WARN] Custom selection bypasses RAM safety checks.\033[0m")
        selected_model = questionary.text(
            "Enter the exact Ollama model tag (e.g., 'qwen2.5-coder:14b'):"
        ).ask()

    return selected_model

if __name__ == "__main__":
    model = select_initial_model()
    if model and model != "skip":
        print(f"\n\033[0;32m[OK] You selected: {model}. Ready to pull.\033[0m")
    else:
        print("\n[INFO] Installation skipped.")