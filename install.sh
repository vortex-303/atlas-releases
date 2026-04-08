#!/bin/bash
# Atlas Agent Installer
# Usage: curl -fsSL https://atlasagent.dev/install.sh | sh
set -e

echo ""
echo "  ╔═══════════════════════════════════╗"
echo "  ║       Atlas Agent Installer       ║"
echo "  ║   AI Business Automation for Mac  ║"
echo "  ╚═══════════════════════════════════╝"
echo ""

# --- Config ---
ATLAS_DIR="$HOME/.atlas"
BIN_DIR="$ATLAS_DIR/bin"
DATA_DIR="$ATLAS_DIR/data"
LOG_DIR="$ATLAS_DIR/logs"
APP_DIR="$HOME/Applications"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/dev.atlasagent.plist"
REPO="vortex-303/atlas-releases"
PORT=8642

# --- Detect platform ---
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ Atlas Agent requires macOS."
    exit 1
fi

ARCH=$(uname -m)  # arm64 or x86_64
echo "  Platform: macOS ($ARCH)"

# --- Check if already installed ---
if [ -f "$BIN_DIR/atlas-server" ]; then
    echo "  Atlas Agent is already installed."
    read -p "  Reinstall/update? [Y/n] " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        echo "  Cancelled."
        exit 0
    fi
    # Stop existing server
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    sleep 1
fi

# --- Get latest release ---
echo ""
echo "  Downloading latest release..."
LATEST=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$LATEST" ]; then
    echo "  ⚠️  Could not fetch latest release. Using direct download."
    LATEST="v1.0.0"
fi
echo "  Version: $LATEST"

# --- Create directories ---
mkdir -p "$BIN_DIR" "$DATA_DIR" "$LOG_DIR" "$APP_DIR"

# --- Download app bundle ---
echo "  Downloading Atlas Agent ($ARCH)..."
ZIP_URL="https://github.com/$REPO/releases/download/$LATEST/AtlasAgent-${LATEST#v}-$ARCH.zip"
TEMP_DIR=$(mktemp -d)

if curl -fL "$ZIP_URL" -o "$TEMP_DIR/atlas.zip" 2>/dev/null; then
    cd "$TEMP_DIR"
    unzip -q atlas.zip
    # Remove old app if exists
    rm -rf "$APP_DIR/Atlas Agent.app" 2>/dev/null
    cp -R "Atlas Agent.app" "$APP_DIR/"
    # Extract server binary from app bundle
    if [ -f "Atlas Agent.app/Contents/Resources/bin/atlas-server" ]; then
        cp "Atlas Agent.app/Contents/Resources/bin/atlas-server" "$BIN_DIR/atlas-server"
    fi
    chmod +x "$BIN_DIR/atlas-server"
    # Remove quarantine flag
    xattr -rd com.apple.quarantine "$APP_DIR/Atlas Agent.app" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    cd "$HOME"
    echo "  ✓ Atlas Agent.app installed"
    echo "  ✓ Server binary installed"
else
    echo "  ⚠️  App download failed. Trying binary-only..."
    BIN_URL="https://github.com/$REPO/releases/download/$LATEST/atlas-server-$ARCH"
    if curl -fL "$BIN_URL" -o "$BIN_DIR/atlas-server" 2>/dev/null; then
        chmod +x "$BIN_DIR/atlas-server"
        echo "  ✓ Server binary installed (no .app bundle)"
    else
        echo "  ❌ Download failed. Check https://github.com/$REPO/releases"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    rm -rf "$TEMP_DIR"
fi

# --- Create launchd service ---
echo "  Setting up auto-start..."
cat > "$LAUNCH_AGENT" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.atlasagent.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN_DIR}/atlas-server</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/server.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/server.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ATLAS_DATA_DIR</key>
        <string>${DATA_DIR}</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>${ATLAS_DIR}</string>
</dict>
</plist>
PLIST

echo "  ✓ Launch agent created"

# --- Create uninstall command ---
cat > "$BIN_DIR/atlas-uninstall" << 'UNINSTALL'
#!/bin/bash
exec "$(dirname "$0")/../../atlas-agent/uninstall.sh" 2>/dev/null || \
    curl -fsSL https://atlasagent.dev/uninstall.sh | sh
UNINSTALL
chmod +x "$BIN_DIR/atlas-uninstall"

# --- Start server ---
echo "  Starting Atlas Agent..."
launchctl load "$LAUNCH_AGENT"


# --- Wait for server ---
echo "  Waiting for server to start..."
for i in $(seq 1 20); do
    if curl -s "http://localhost:$PORT/api/status" >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

# --- Open browser ---
if curl -s "http://localhost:$PORT/api/status" >/dev/null 2>&1; then
    sleep 1
    open "http://localhost:$PORT"
    echo ""
    echo "  ╔═══════════════════════════════════╗"
    echo "  ║     ✅ Atlas Agent Installed!      ║"
    echo "  ╚═══════════════════════════════════╝"
else
    echo ""
    echo "  ⚠️  Server may still be starting..."
fi

echo ""
echo "  Server:     http://localhost:$PORT"
echo "  Binary:     $BIN_DIR/atlas-server"
echo "  Data:       $DATA_DIR/"
echo "  Logs:       $LOG_DIR/"
echo ""
echo "  Auto-starts on login. Look for 'A' in menu bar."
echo "  To uninstall: atlas-uninstall"
echo ""
