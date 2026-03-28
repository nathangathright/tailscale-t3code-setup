# Remote Coding Setup with Tailscale and t3code

Automated setup script for remote coding from a remote device using Tailscale and [t3code](https://github.com/pingdotgg/t3code).

This setup lets you leave the computing power at home and connect from a lightweight remote device. Your computer stays on, runs your coding agents, and is intended to be accessed from devices on your private Tailscale network.

## Quick Start

On the computer you want to access remotely:

Prerequisites:
- [Homebrew](https://brew.sh)
- [Node.js](https://nodejs.org) 22.16+, 23.11+, or 24.10+ installed
- At least one supported coding-agent CLI installed: [Claude Code](https://code.claude.com/docs/en/overview#get-started) or [Codex CLI](https://developers.openai.com/codex/cli)

```bash
curl -fsSL https://raw.githubusercontent.com/nathangathright/tailscale-t3code-setup/main/setup.sh | bash
```

On your remote device, install Tailscale, then open a browser and go to `http://<tailscale-hostname>:3773` to start coding. The setup script prints your Tailscale hostname at the end.

## What the Script Does

- Installs Tailscale (CLI version) for encrypted networking between devices
- Installs [t3code](https://github.com/pingdotgg/t3code), a web GUI for AI coding agents (Claude and Codex), as a launchd service on port 3773
- Installs the [tailserve](https://github.com/nathangathright/tailserve) skill into your detected coding agent CLIs so they know how to preview web projects over Tailscale

Tailscale encrypts traffic end-to-end. In the default workflow, you access t3code from devices on your private Tailscale network.

## Daily Workflow

1. Set up your remote device and input devices.
2. Open a browser and go to `http://<tailscale-hostname>:3773`.
3. Start or resume Claude and Codex sessions in the t3code web UI.
4. Close the browser when you leave. Your sessions keep running on your computer.

## Previewing Web Projects

Since your remote device and computer are on the same Tailscale network, any dev server running on your computer is already accessible from your remote device. For direct access, bind your dev server to `0.0.0.0` instead of `localhost`, then open `http://<hostname>:<port>` in your browser.

The setup script installs the [tailserve](https://github.com/nathangathright/tailserve) skill that teaches AI coding agents the correct commands for every framework (Vite, Next.js, Wrangler, etc.). Just ask your coding agent to "preview this project over Tailscale" and it will know what to do.

tailserve covers three approaches:
- **Direct tailnet access** — bind to `0.0.0.0`, access via `http://<hostname>:<port>`
- **`tailscale serve`** — automatic HTTPS, path-based routing for multiple projects

## Uninstalling

```bash
launchctl bootout gui/$(id -u)/com.t3code.server
rm ~/Library/LaunchAgents/com.t3code.server.plist
npm uninstall -g t3
sudo tailscaled uninstall-system-daemon || true
brew uninstall tailscale
npx skills remove --global --agent '*' tailserve -y
```

## License

MIT
