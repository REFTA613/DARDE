#!/bin/bash
set -e

# Prevents Python from leaving trash on the disk
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUNBUFFERED=1

cd "$(dirname "$0")"

# Virtual Environment setup
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate

# Esegue l'aggiornamento di pip alla luce del sole (senza maschere)
python3 -m pip install --upgrade pip

# Installa i requisiti mostrando l'output reale
pip install -r requirements.txt

# Run main.py directly
python main.py

deactivate