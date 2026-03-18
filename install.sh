#!/usr/bin/env bash
set -euo pipefail

APP_NAME="tensoragent"
APP_DIR="$HOME/.tensoragent"
REPO_URL="https://github.com/kerodem/TensorAgent/archive/refs/heads/main.zip"

echo "Installing $APP_NAME..."

# --- Requirements ---
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Python3 is required."
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "❌ unzip is required."
  exit 1
fi

# --- tmux check ---
if ! command -v tmux >/dev/null 2>&1; then
  echo "⚠️ Installing tmux..."
  if command -v brew >/dev/null; then
    brew install tmux
  elif command -v apt >/dev/null; then
    sudo apt install -y tmux
  else
    echo "❌ Please install tmux manually."
    exit 1
  fi
fi

# --- Clean install ---
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "Downloading TensorAgent..."
curl -fsSL "$REPO_URL" -o repo.zip
unzip -q repo.zip
cd TensorAgent-main

cp -r * "$APP_DIR"

# --- Create CLI wrapper ---
cat << 'EOF' > "$APP_DIR/tensoragent"
#!/usr/bin/env bash
python3 "$HOME/.tensoragent/scripts/native_llm_terminal.py" "$@"
EOF

chmod +x "$APP_DIR/tensoragent"

# --- GLOBAL INSTALL (STRICT ONE-SHOT) ---
echo "Linking TensorAgent globally (requires password)..."

# Force sudo authentication upfront
if ! sudo -v; then
  echo "❌ Sudo access is required to install TensorAgent."
  exit 1
fi

# Create symlink
sudo ln -sf "$APP_DIR/tensoragent" /usr/local/bin/tensoragent

# --- VERIFY INSTALL ---
if [ ! -f "/usr/local/bin/tensoragent" ]; then
  echo "❌ Failed to link TensorAgent into /usr/local/bin"
  exit 1
fi

# Refresh shell command cache
hash -r 2>/dev/null || true

# Final check
if ! command -v tensoragent >/dev/null 2>&1; then
  echo "❌ Installation verification failed."
  exit 1
fi

echo
echo "✅ Installed TensorAgent successfully"
echo
echo "Run:"
echo "  tensoragent orchestrate"
