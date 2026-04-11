#!/bin/bash
# Remote Coding Setup Script
# Sets up a computer or server for remote access via Tailscale and t3code

set -e  # Exit on error

T3_REQUIRED_NODE_RANGE="^22.16 || ^23.11 || >=24.10"
T3_PORT_DEFAULT="3773"
T3_PORT="${T3_PORT:-$T3_PORT_DEFAULT}"
TAILSCALE_APP_PATH="/Applications/Tailscale.app"
TAILSCALE_APP_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
T3_BASE_DIR="$HOME/.t3"
T3_USERDATA_DIR="$T3_BASE_DIR/userdata"
T3_LOG_DIR="$T3_USERDATA_DIR/logs"
T3_WRAPPER_PATH="$T3_BASE_DIR/run-t3code.sh"
T3_MACOS_LABEL="com.t3code.server"
T3_LINUX_SERVICE_NAME="t3code-$(id -un).service"
SERVICE_PATH=""
PAIR_URL=""

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

get_tailscale_ipv4() {
    tailscale_exec ip -4 2>/dev/null | awk 'NF {print; exit}'
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

validate_t3_port() {
    if ! [[ "$T3_PORT" =~ ^[0-9]+$ ]] || [ "$T3_PORT" -lt 1 ] || [ "$T3_PORT" -gt 65535 ]; then
        echo "❌ Error: T3_PORT must be an integer between 1 and 65535."
        exit 1
    fi
}

port_available_on_host() {
    local host="$1"
    local port="$2"

    T3_BIND_HOST="$host" T3_BIND_PORT="$port" node <<'NODE'
const net = require("net");

const host = process.env.T3_BIND_HOST;
const port = Number(process.env.T3_BIND_PORT);

const server = net.createServer();
server.once("error", () => process.exit(1));
server.once("listening", () => {
  server.close(() => process.exit(0));
});
server.listen({ host, port });
NODE
}

ensure_t3_runtime_config() {
    mkdir -p "$T3_USERDATA_DIR" "$T3_LOG_DIR"
}

build_service_path() {
    echo "${PATH}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
}

stop_managed_t3code_service() {
    case "$OS_FAMILY" in
        macos)
            launchctl bootout "gui/$(id -u)/${T3_MACOS_LABEL}" 2>/dev/null || true
            ;;
        linux)
            if command -v systemctl &> /dev/null; then
                sudo systemctl stop "$T3_LINUX_SERVICE_NAME" 2>/dev/null || true
            fi
            ;;
    esac
}

write_t3_wrapper() {
    local tailscale_ip="$1"

    cat > "$T3_WRAPPER_PATH" <<EOF
#!/bin/bash
set -euo pipefail

export HOME="$HOME"
export PATH="$SERVICE_PATH"

exec "$NODE_BIN" "$T3_BIN" serve --base-dir "$T3_BASE_DIR" --host "$tailscale_ip" --port "$T3_PORT"
EOF
    chmod 700 "$T3_WRAPPER_PATH"
}

capture_t3_pairing_link() {
    local output=""
    local attempt=""
    local raw_pair_url=""

    for attempt in $(seq 1 20); do
        case "$OS_FAMILY" in
            macos)
                if [ -f "${T3_LOG_DIR}/launchd-stdout.log" ]; then
                    output="$(tail -n 200 "${T3_LOG_DIR}/launchd-stdout.log" 2>/dev/null || true)"
                fi
                ;;
            linux)
                output="$(sudo journalctl -u "$T3_LINUX_SERVICE_NAME" -n 200 --no-pager -o cat 2>/dev/null || true)"
                ;;
        esac

        raw_pair_url="$(printf '%s\n' "$output" | grep -Eo 'https?://[^[:space:]]+/pair#token=[^[:space:]]+' | tail -n 1 || true)"
        if [ -n "$raw_pair_url" ]; then
            PAIR_URL="$(PAIR_URL="$raw_pair_url" T3_DISPLAY_HOST="$TAILSCALE_HOST" T3_DISPLAY_PORT="$T3_PORT" node -e '
const url = new URL(process.env.PAIR_URL);
url.hostname = process.env.T3_DISPLAY_HOST;
url.port = process.env.T3_DISPLAY_PORT;
process.stdout.write(url.toString());
')"
            return 0
        fi

        sleep 1
    done

    return 1
}

echo "✓ Detected platform: ${OS_FAMILY}"

validate_t3_port

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

TAILSCALE_IP="$(get_tailscale_ipv4)"
if [ -z "$TAILSCALE_IP" ]; then
    echo "❌ Error: Could not determine the machine's Tailscale IPv4 address."
    echo "Make sure Tailscale is connected, then re-run this script."
    exit 1
fi
echo "✓ Tailscale IPv4 detected: ${TAILSCALE_IP}"

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
echo "Installing latest t3code..."
npm install -g t3@latest
echo "✓ t3code is up to date"

NODE_BIN="$(command -v node)"
T3_BIN="$(command -v t3)"
SERVICE_PATH="$(build_service_path)"

ensure_t3_runtime_config

stop_managed_t3code_service

if ! port_available_on_host "$TAILSCALE_IP" "$T3_PORT"; then
    echo "❌ Error: Port ${T3_PORT} is not available on ${TAILSCALE_IP}."
    if [ "$T3_PORT" = "$T3_PORT_DEFAULT" ]; then
        echo "Free that port or re-run with a different port, for example:"
        echo "  curl -fsSL https://raw.githubusercontent.com/nathangathright/tailscale-t3code-setup/main/setup.sh | T3_PORT=4000 bash"
    else
        echo "Choose a different T3_PORT, then re-run this script."
    fi
    exit 1
fi

write_t3_wrapper "$TAILSCALE_IP"

install_t3code_service() {
    echo ""
    echo "🔄 Setting up t3code to start automatically..."

    case "$OS_FAMILY" in
        macos)
            local plist_label plist_path
            plist_label="$T3_MACOS_LABEL"
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
        <string>${T3_WRAPPER_PATH}</string>
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
        <string>${SERVICE_PATH}</string>
    </dict>
</dict>
</plist>
PLIST

            launchctl bootout "gui/$(id -u)/${plist_label}" 2>/dev/null || true
            launchctl bootstrap "gui/$(id -u)" "$plist_path"
            ;;
        linux)
            local service_name service_path
            service_name="$T3_LINUX_SERVICE_NAME"
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
Environment=PATH=${SERVICE_PATH}
ExecStart=${T3_WRAPPER_PATH}
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

capture_t3_pairing_link || true

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
echo "  Bind:   http://${TAILSCALE_IP}:${T3_PORT}"
echo "  Remote: http://${TAILSCALE_HOST}:${T3_PORT}"
if [ -n "$PAIR_URL" ]; then
    echo "  Pair:   ${PAIR_URL}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. On your remote device, install Tailscale and sign in with the same account"
if [ -n "$PAIR_URL" ]; then
    echo "2. Open a browser and go to the pairing URL above"
else
    echo "2. Open http://${TAILSCALE_HOST}:${T3_PORT} and use the Pairing URL from the service logs if prompted"
fi
echo ""
echo "Happy remote coding!"
