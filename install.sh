#!/usr/bin/env bash
set -euo pipefail

APP_NAME="tensoragent"
INSTALL_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.tensoragent"
REPO_URL="https://codeload.github.com/kerodem/TensorAgent/zip/refs/heads/main"

echo "Installing $APP_NAME..."

# Python check
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Python3 required."
  exit 1
fi

# tmux check
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

mkdir -p "$INSTALL_DIR"
mkdir -p "$APP_DIR"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

curl -fsSL "$REPO_URL" -o repo.zip
unzip -q repo.zip

cp -r TensorAgent-main/* "$APP_DIR"

# Create CLI
cat << 'EOF' > "$APP_DIR/tensoragent"
#!/usr/bin/env bash
python3 "$HOME/.tensoragent/scripts/native_llm_terminal.py" "$@"
EOF

chmod +x "$APP_DIR/tensoragent"
ln -sf "$APP_DIR/tensoragent" "$INSTALL_DIR/tensoragent"

echo
echo "✅ Installed TensorAgent"
echo "Run: tensoragent orchestrate"
