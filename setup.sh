#!/bin/bash
# iPad Remote Coding Setup Script
# Sets up a Mac for remote access via Tailscale SSH and tmux

set -e  # Exit on error

echo "🚀 Setting up Mac for remote coding from iPad..."
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
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "✓ Homebrew already installed"
fi

# Install Tailscale
echo ""
echo "📡 Installing Tailscale CLI..."
if ! command -v tailscale &> /dev/null; then
    brew install tailscale
    echo "✓ Tailscale installed"
else
    echo "✓ Tailscale already installed"
fi

# Start Tailscale with SSH enabled
echo ""
echo "🔐 Checking Tailscale SSH..."
ensure_tailscale_daemon_ready
if ! tailscale status &> /dev/null; then
    echo "Please authenticate Tailscale in the browser window that opens..."
    sudo tailscale up --ssh
    echo "✓ Tailscale SSH enabled"
else
    # Check if SSH is already enabled
    SSH_ENABLED=$(tailscale debug prefs 2>/dev/null | grep -c '"RunSSH": true' || echo 0)
    if [ "$SSH_ENABLED" -eq 0 ]; then
        echo "Enabling SSH (requires sudo)..."
        sudo tailscale up --ssh
        echo "✓ Tailscale SSH enabled"
    else
        echo "✓ Tailscale SSH already enabled"
    fi
fi

# Get Tailscale hostname
# Extract the hostname for the current machine (first line with this machine's IP)
TAILSCALE_HOST=$(tailscale status --self=true | awk 'NR==1 {print $2}')
if [ -z "$TAILSCALE_HOST" ]; then
    # Fallback: strip .local from system hostname
    TAILSCALE_HOST=$(hostname | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]')
fi

# Install tmux
echo ""
echo "🖥️  Installing and configuring tmux..."
if ! command -v tmux &> /dev/null; then
    brew install tmux
    echo "✓ tmux installed"
else
    echo "✓ tmux already installed"
fi

# Install qrencode for QR code generation
echo ""
echo "📱 Installing qrencode for QR code display..."
if ! command -v qrencode &> /dev/null; then
    brew install qrencode
    echo "✓ qrencode installed"
else
    echo "✓ qrencode already installed"
fi

# Create tmux config
echo ""
echo "📝 Creating tmux configuration..."
TMUX_MAIN_CONFIG="$HOME/.tmux.conf"
TMUX_REMOTE_CONFIG="$HOME/.tmux.remote-coding.conf"
cat > "$TMUX_REMOTE_CONFIG" << 'EOF'
# Enable mouse support
set -g mouse on

# Increase scrollback buffer
set -g history-limit 10000

# Better terminal type for modern terminals
set -g default-terminal "tmux-256color"

# Terminal overrides for better color and mouse support
set -ga terminal-overrides ",xterm-256color:Tc"
set -ga terminal-overrides ",*256col*:Tc"

# Fast escape time (better responsiveness)
set -sg escape-time 10

# Focus events for better terminal integration
set -g focus-events on

# Status bar styling
set -g status-style bg=black,fg=white
set -g status-right '#[fg=cyan]%Y-%m-%d %H:%M'
EOF
echo "✓ Managed tmux profile written to $TMUX_REMOTE_CONFIG"

TMUX_INCLUDE_LINE="source-file ~/.tmux.remote-coding.conf"
if [ ! -f "$TMUX_MAIN_CONFIG" ]; then
    cat > "$TMUX_MAIN_CONFIG" << 'EOF'
source-file ~/.tmux.remote-coding.conf
EOF
    echo "✓ Created $TMUX_MAIN_CONFIG and linked managed profile"
elif ! grep -Fq ".tmux.remote-coding.conf" "$TMUX_MAIN_CONFIG"; then
    echo "" >> "$TMUX_MAIN_CONFIG"
    echo "# iPad remote coding setup (managed include)" >> "$TMUX_MAIN_CONFIG"
    echo "$TMUX_INCLUDE_LINE" >> "$TMUX_MAIN_CONFIG"
    echo "✓ Added managed profile include to $TMUX_MAIN_CONFIG"
else
    echo "✓ Existing $TMUX_MAIN_CONFIG already includes managed profile"
fi

# Install sesh (tmux session manager for AI coding agents)
echo ""
echo "☕ Installing sesh..."
curl -fsSL https://raw.githubusercontent.com/nathangathright/sesh/main/install.sh | bash

# Add unlock function
SHELL_CONFIG=""
if [ -f ~/.zshrc ]; then
    SHELL_CONFIG=~/.zshrc
elif [ -f ~/.bashrc ]; then
    SHELL_CONFIG=~/.bashrc
elif [ -f ~/.bash_profile ]; then
    SHELL_CONFIG=~/.bash_profile
fi

if [ -z "$SHELL_CONFIG" ]; then
    SHELL_CONFIG=~/.zshrc
    touch "$SHELL_CONFIG"
    echo "✓ Created $SHELL_CONFIG for shell helpers"
fi

if [ -n "$SHELL_CONFIG" ]; then
    if ! grep -q "unlock()" "$SHELL_CONFIG" 2>/dev/null; then
        echo "" >> "$SHELL_CONFIG"
        echo "# Unlock macOS keychain (locked by default over SSH)" >> "$SHELL_CONFIG"
        cat >> "$SHELL_CONFIG" << 'FUNC'
unlock() {
  if security show-keychain-info ~/Library/Keychains/login.keychain-db 2>/dev/null; then
    echo "🔓 Keychain is already unlocked"
  else
    security unlock-keychain ~/Library/Keychains/login.keychain-db
  fi
}
FUNC
        echo "✓ 'unlock' function added to $SHELL_CONFIG"
    else
        echo "✓ 'unlock' function already exists"
    fi
fi

# Install tailserve skill for AI coding agents
echo ""
echo "📚 Installing tailserve skill for AI coding agents..."
TAILSERVE_DIR="$HOME/Developer/tailserve"

if [ ! -d "$TAILSERVE_DIR" ]; then
    git clone https://github.com/nathangathright/tailserve.git "$TAILSERVE_DIR"
else
    echo "  tailserve repo already present at $TAILSERVE_DIR"
fi

bash "$TAILSERVE_DIR/install.sh"
echo "✓ tailserve skill installed"

# Build SSH URL for QR code
SSH_URL="ssh://$(whoami)@${TAILSCALE_HOST}"

# Display connection information
echo ""
echo "✅ Setup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📱 iPad Connection Details:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Hostname: $TAILSCALE_HOST"
echo "Username: $(whoami)"
echo "Authentication: Tailscale SSH (automatic)"
echo ""

# Display QR code if qrencode is available
if command -v qrencode &> /dev/null; then
    echo "Scan this QR code from your iPad to open in Termius:"
    echo ""
    qrencode -t UTF8 "$SSH_URL"
    echo ""
    echo "URL: $SSH_URL"
else
    echo "URL: $SSH_URL"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. On your iPad, install Tailscale and Termius from the App Store"
echo "2. Sign into Tailscale with the same account"
echo "3. Scan the QR code above, or manually create a new host in Termius:"
echo "   - Hostname: $TAILSCALE_HOST"
echo "   - Username: $(whoami)"
echo "   - Authentication: Default settings"
echo "4. Connect and run: sesh new"
echo "5. Run 'unlock' if you need git or keychain access"
echo ""
echo "Shell functions:"
echo "  sesh new                  # Interactive session wizard"
echo "  sesh myproject ~/code     # Create/attach 'myproject' session at ~/code"
echo "  sesh -s work -p ~/app     # Using named parameters"
echo "  sesh list                 # Pick from existing sessions"
echo "  unlock                   # Unlock macOS keychain over SSH"
echo ""
echo "To start using these commands:"
echo "  source $SHELL_CONFIG  # Load the new functions and aliases"
echo ""
echo "Happy remote coding! ☕"
