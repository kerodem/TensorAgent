#!/usr/bin/env bash
set -euo pipefail

APP_NAME="tensoragent"
APP_DIR="$HOME/.tensoragent"
REPO_URL="https://github.com/kerodem/TensorAgent/archive/refs/heads/main.zip"

echo "Installing $APP_NAME..."

# --- Check Python ---
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Python3 required."
  exit 1
fi

# --- Check tmux ---
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

# --- Check unzip ---
if ! command -v unzip >/dev/null 2>&1; then
  echo "❌ unzip required."
  exit 1
fi

# --- Prepare install dir ---
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "Downloading TensorAgent..."
curl -fsSL "$REPO_URL" -o repo.zip
unzip -q repo.zip
cd TensorAgent-main

# --- Copy files ---
cp -r * "$APP_DIR"

# --- Create CLI wrapper ---
cat << 'EOF' > "$APP_DIR/tensoragent"
#!/usr/bin/env bash
python3 "$HOME/.tensoragent/scripts/native_llm_terminal.py" "$@"
EOF

chmod +x "$APP_DIR/tensoragent"

# --- Setup user-level binary ---
echo "Setting up TensorAgent..."

mkdir -p "$HOME/.local/bin"
ln -sf "$APP_DIR/tensoragent" "$HOME/.local/bin/tensoragent"

# Make it available immediately
export PATH="$HOME/.local/bin:$PATH"

echo "✅ Installed TensorAgent"

# --- Persist PATH if needed ---
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo
  echo "Add this to your shell config (~/.zshrc or ~/.bashrc):"
  echo 'export PATH="$HOME/.local/bin:$PATH"'
fi

echo
echo "Run:"
echo "  tensoragent orchestrate"
