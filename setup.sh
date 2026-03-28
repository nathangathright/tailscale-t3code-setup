#!/bin/bash
# Remote Coding Setup Script
# Sets up a computer for remote access via Tailscale and t3code

set -e  # Exit on error

echo "🚀 Setting up computer for remote coding from another device..."
echo ""

# Ensure the Tailscale daemon is reachable before running tailscale up.
ensure_tailscale_daemon_ready() {
    local status_output
    if tailscale status &> /dev/null; then
        return 0
    fi

    status_output="$(tailscale status 2>&1 || true)"

    # If status fails for auth/login reasons (daemon is up), let the main flow run tailscale up.
    if ! echo "$status_output" | grep -Eiq 'failed to connect|cannot connect|connect to local tailscaled|dial unix|tailscaled.*not running'; then
        return 0
    fi

    echo "Tailscale daemon not reachable. Attempting to install/start system daemon..."

    if ! command -v tailscaled &> /dev/null; then
        echo "❌ Error: tailscaled not found after tailscale install."
        return 1
    fi

    sudo tailscaled install-system-daemon || true

    local attempt
    for attempt in 1 2 3 4 5; do
        sleep 2
        if tailscale status &> /dev/null; then
            echo "✓ Tailscale daemon is ready"
            return 0
        fi
    done

    echo "❌ Error: Tailscale daemon is still not reachable."
    echo "Try running:"
    echo "  sudo tailscaled install-system-daemon"
    echo "  tailscale status"
    return 1
}

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ Error: This script is designed for macOS only"
    exit 1
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Error: Homebrew is required but not installed."
    echo "Install it first: https://brew.sh"
    exit 1
fi
echo "✓ Homebrew installed"

# Install Tailscale
echo ""
echo "📡 Installing Tailscale CLI..."
if ! command -v tailscale &> /dev/null; then
    brew install tailscale
    echo "✓ Tailscale installed"
else
    echo "✓ Tailscale already installed"
fi

# Start Tailscale
echo ""
echo "🔐 Starting Tailscale..."
ensure_tailscale_daemon_ready
if ! tailscale status &> /dev/null; then
    echo "Please authenticate Tailscale in the browser window that opens..."
    sudo tailscale up
    echo "✓ Tailscale connected"
else
    echo "✓ Tailscale already connected"
fi

# Get Tailscale hostname
TAILSCALE_HOST=$(tailscale status --self=true | awk 'NR==1 {print $2}')
if [ -z "$TAILSCALE_HOST" ]; then
    TAILSCALE_HOST=$(hostname | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]')
fi

# Check if Node.js is installed
echo ""
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is required but not installed."
    echo "Install it from https://nodejs.org or via nvm:"
    echo "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash"
    echo "  nvm install --lts"
    exit 1
else
    echo "✓ Node.js $(node --version) installed"
fi

# Check if at least one supported coding-agent CLI is installed
AGENT_TARGETS=()

if command -v claude &> /dev/null; then
    AGENT_TARGETS+=("claude-code")
fi

if command -v codex &> /dev/null; then
    AGENT_TARGETS+=("codex")
fi

if [ ${#AGENT_TARGETS[@]} -eq 0 ]; then
    echo "❌ Error: Install at least one supported coding-agent CLI first."
    echo "  Claude Code: https://code.claude.com/docs/en/overview#get-started"
    echo "  Codex CLI:   https://developers.openai.com/codex/cli"
    exit 1
fi
echo "✓ Supported coding-agent CLI detected for: ${AGENT_TARGETS[*]}"

# Install t3code (web GUI for coding agents)
echo ""
echo "☕ Installing t3code..."
if ! command -v t3 &> /dev/null; then
    npm install -g t3
    echo "✓ t3code installed"
else
    echo "✓ t3code already installed"
fi

# Set up launchd service for t3code
PLIST_LABEL="com.t3code.server"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
echo ""
echo "🔄 Setting up t3code to start automatically..."
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which node)</string>
        <string>$(which t3)</string>
        <string>--no-browser</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/.t3/userdata/logs/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.t3/userdata/logs/launchd-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname $(which node)):$(dirname $(which t3)):/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLIST

# Ensure log directory exists
mkdir -p "$HOME/.t3/userdata/logs"

# Load the service (unload first if already loaded)
launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
echo "✓ t3code service installed and started (port 3773)"

# Install tailserve skill for detected coding agents
echo ""
echo "📚 Installing tailserve skill for detected coding agents..."
npx skills add nathangathright/tailserve -g -a "${AGENT_TARGETS[@]}" -y
echo "✓ tailserve skill installed for: ${AGENT_TARGETS[*]}"

# Display connection information
echo ""
echo "✅ Setup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "t3code is running at:"
echo ""
echo "  Local:  http://localhost:3773"
echo "  Remote: http://${TAILSCALE_HOST}:3773"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. On your remote device, install Tailscale and sign in with the same account"
echo "2. Open a browser and go to: http://${TAILSCALE_HOST}:3773"
echo ""
echo "Happy remote coding! ☕"
