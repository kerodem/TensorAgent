#!/usr/bin/env bash
set -euo pipefail

APP_NAME="tensoragent"
INSTALL_DIR="/usr/local/bin"
APP_DIR="$HOME/.tensoragent"
REPO_URL="https://github.com/kerodem/TensorAgent/archive/refs/heads/main.zip"

echo "Installing $APP_NAME..."

# --- Checks ---
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Python3 required."
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "⚠️ Installing tmux..."
  if command -v brew >/dev/null; then
    brew install tmux
  elif command -v apt >/dev/null; then
    sudo apt install -y tmux
  else
    echo "❌ Install tmux manually."
    exit 1
  fi
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "❌ unzip required."
  exit 1
fi

# --- Prepare dirs ---
mkdir -p "$APP_DIR"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "Downloading..."
curl -fsSL "$REPO_URL" -o repo.zip
unzip -q repo.zip
cd TensorAgent-main

# Clean install
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp -r * "$APP_DIR"

# --- Create CLI ---
cat << 'EOF' > "$APP_DIR/tensoragent"
#!/usr/bin/env bash
python3 "$HOME/.tensoragent/scripts/native_llm_terminal.py" "$@"
EOF

chmod +x "$APP_DIR/tensoragent"

# --- Linking ---
echo "Linking TensorAgent..."

if sudo ln -sf "$APP_DIR/tensoragent" /usr/local/bin/tensoragent; then
  echo "✅ Linked to /usr/local/bin"
else
  echo "❌ Failed to link"
  exit 1
fi

# --- Final verify ---
if [ -f "/usr/local/bin/tensoragent" ]; then
  echo
  echo "✅ Installed TensorAgent"
  echo "Run: tensoragent orchestrate"
else
  echo "❌ Installation failed"
  exit 1
fi
