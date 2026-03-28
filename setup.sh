#!/bin/bash
# Remote Coding Setup Script
# Sets up a computer or server for remote access via Tailscale and t3code

set -e  # Exit on error

T3_REQUIRED_NODE_RANGE="^22.16 || ^23.11 || >=24.10"
T3_PORT="3773"
TAILSCALE_APP_PATH="/Applications/Tailscale.app"
TAILSCALE_APP_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

echo "🚀 Setting up computer for remote coding from another device..."
echo ""

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        *)
            echo "❌ Error: Unsupported operating system: $(uname -s)"
            echo "This script currently supports macOS and Linux."
            exit 1
            ;;
    esac
}

OS_FAMILY="$(detect_os)"

install_tailscale() {
    echo ""
    echo "📡 Installing Tailscale..."

    if tailscale_install_present; then
        echo "✓ Tailscale already installed"
        return 0
    fi

    case "$OS_FAMILY" in
        macos)
            if command -v tailscale &> /dev/null; then
                echo "Detected a non-app Tailscale CLI on PATH."
                echo "This setup expects the standalone macOS Tailscale app."
            fi
            echo "Tailscale for macOS is installed via the standalone app from Tailscale's package server."
            echo "Opening the download page now. Install the standalone app, launch it, and finish the onboarding flow."
            open "https://tailscale.com/download/mac"

            local attempt
            for attempt in $(seq 1 90); do
                sleep 2
                if tailscale_install_present; then
                    echo "✓ Tailscale app detected"
                    return 0
                fi
            done

            echo "❌ Error: Tailscale was not detected after waiting for the macOS app install."
            echo "Install the standalone Tailscale app from https://tailscale.com/download/mac, then re-run this script."
            exit 1
            ;;
        linux)
            if ! command -v curl &> /dev/null; then
                echo "❌ Error: curl is required to install Tailscale on Linux."
                exit 1
            fi
            curl -fsSL https://tailscale.com/install.sh | sh
            ;;
    esac

    echo "✓ Tailscale installed"
}

tailscale_install_present() {
    if [ "$OS_FAMILY" = "macos" ]; then
        [ -d "$TAILSCALE_APP_PATH" ] && [ -x "$TAILSCALE_APP_CLI" ]
    else
        command -v tailscale &> /dev/null
    fi
}

tailscale_exec() {
    if [ "$OS_FAMILY" = "macos" ] && [ -x "$TAILSCALE_APP_CLI" ]; then
        "$TAILSCALE_APP_CLI" "$@"
    elif command -v tailscale &> /dev/null; then
        command tailscale "$@"
    else
        echo "❌ Error: Tailscale CLI not found."
        exit 1
    fi
}

start_tailscale_daemon() {
    case "$OS_FAMILY" in
        macos)
            open -a Tailscale || true
            ;;
        linux)
            if command -v systemctl &> /dev/null; then
                sudo systemctl enable --now tailscaled
            else
                echo "❌ Error: systemd is required on Linux to manage the Tailscale daemon."
                exit 1
            fi
            ;;
    esac
}

# Ensure the Tailscale daemon is reachable before running tailscale up.
ensure_tailscale_daemon_ready() {
    local status_output
    if tailscale_exec status &> /dev/null; then
        return 0
    fi

    status_output="$(tailscale_exec status 2>&1 || true)"

    # If status fails for auth/login reasons (daemon is up), let the main flow run tailscale up.
    if ! echo "$status_output" | grep -Eiq 'failed to connect|cannot connect|connect to local tailscaled|dial unix|tailscaled.*not running'; then
        return 0
    fi

    echo "Tailscale daemon not reachable. Attempting to install/start system daemon..."

    start_tailscale_daemon

    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        if tailscale_exec status &> /dev/null; then
            echo "✓ Tailscale daemon is ready"
            return 0
        fi
    done

    echo "❌ Error: Tailscale daemon is still not reachable."
    echo "Try running:"
    if [ "$OS_FAMILY" = "macos" ]; then
        echo "  open -a Tailscale"
        echo "  /Applications/Tailscale.app/Contents/MacOS/Tailscale status"
    else
        echo "  sudo systemctl enable --now tailscaled"
        echo "  tailscale status"
    fi
    return 1
}

node_version_supported_for_t3() {
    node <<'NODE'
const version = process.versions.node.split(".").map(Number);
const [major, minor] = version;

const supported =
    (major === 22 && minor >= 16) ||
    (major === 23 && minor >= 11) ||
    major >= 24;

process.exit(supported ? 0 : 1);
NODE
}

echo "✓ Detected platform: ${OS_FAMILY}"

install_tailscale

# Start Tailscale
echo ""
echo "🔐 Starting Tailscale..."
ensure_tailscale_daemon_ready
if [ "$OS_FAMILY" = "macos" ]; then
    if ! tailscale_exec status &> /dev/null; then
        echo "Please finish the Tailscale app onboarding flow on this Mac."
        open -a Tailscale || true

        attempt=""
        for attempt in $(seq 1 120); do
            sleep 2
            if tailscale_exec status &> /dev/null; then
                break
            fi
        done

        if ! tailscale_exec status &> /dev/null; then
            echo "❌ Error: Tailscale is not connected yet."
            echo "Complete the Tailscale app onboarding flow, then re-run this script."
            exit 1
        fi
        echo "✓ Tailscale connected"
    else
        echo "✓ Tailscale already connected"
    fi
else
    if ! tailscale_exec status &> /dev/null; then
        echo "Please authenticate Tailscale in the browser window that opens..."
        sudo tailscale up
        echo "✓ Tailscale connected"
    else
        echo "✓ Tailscale already connected"
    fi
fi

# Get Tailscale hostname
TAILSCALE_HOST=$(tailscale_exec status --self=true | awk 'NR==1 {print $2}')
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

if ! node_version_supported_for_t3; then
    echo "❌ Error: Installed Node.js $(node --version) is not supported by t3code."
    echo "t3code currently requires Node.js ${T3_REQUIRED_NODE_RANGE}."
    echo "Upgrade Node.js, then re-run this script."
    exit 1
fi
echo "✓ Node.js version is compatible with t3code"

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
echo "Installing t3code..."
if ! command -v t3 &> /dev/null; then
    npm install -g t3
    echo "✓ t3code installed"
else
    echo "✓ t3code already installed"
fi

NODE_BIN="$(command -v node)"
T3_BIN="$(command -v t3)"
T3_LOG_DIR="$HOME/.t3/userdata/logs"

install_t3code_service() {
    echo ""
    echo "🔄 Setting up t3code to start automatically..."
    mkdir -p "$T3_LOG_DIR"

    case "$OS_FAMILY" in
        macos)
            local plist_label plist_path
            plist_label="com.t3code.server"
            plist_path="$HOME/Library/LaunchAgents/${plist_label}.plist"

            mkdir -p "$HOME/Library/LaunchAgents"
            cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${plist_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_BIN}</string>
        <string>${T3_BIN}</string>
        <string>--no-browser</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${T3_LOG_DIR}/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${T3_LOG_DIR}/launchd-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "${NODE_BIN}"):$(dirname "${T3_BIN}"):/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLIST

            launchctl bootout "gui/$(id -u)/${plist_label}" 2>/dev/null || true
            launchctl bootstrap "gui/$(id -u)" "$plist_path"
            ;;
        linux)
            local service_name service_path
            service_name="t3code-$(id -un).service"
            service_path="/etc/systemd/system/${service_name}"

            sudo tee "$service_path" > /dev/null <<SERVICE
[Unit]
Description=t3code web UI for coding agents
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=$(id -un)
WorkingDirectory=${HOME}
Environment=HOME=${HOME}
Environment=PATH=$(dirname "${NODE_BIN}"):$(dirname "${T3_BIN}"):/usr/local/bin:/usr/bin:/bin
ExecStart=${NODE_BIN} ${T3_BIN} --no-browser
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

            sudo systemctl daemon-reload
            sudo systemctl enable --now "$service_name"
            ;;
    esac

    echo "✓ t3code service installed and started (port ${T3_PORT})"
}

install_t3code_service

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
echo "  Local:  http://localhost:${T3_PORT}"
echo "  Remote: http://${TAILSCALE_HOST}:${T3_PORT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. On your remote device, install Tailscale and sign in with the same account"
echo "2. Open a browser and go to: http://${TAILSCALE_HOST}:${T3_PORT}"
echo ""
echo "Happy remote coding!"
