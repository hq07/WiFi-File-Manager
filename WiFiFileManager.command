#!/bin/bash
cd "$(dirname "$0")"

if ! command -v uv &>/dev/null; then
    echo "Installing uv (first time only)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

echo ""
echo "========================================"
echo "  WiFi File Manager"
echo "  http://localhost:7777"
echo "  Ctrl+C to stop"
echo "========================================"
echo ""

uv run python -m server.main
