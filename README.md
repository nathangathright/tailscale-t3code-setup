# Remote Coding Setup with Tailscale and t3code

Automated setup script for remote coding from a remote device using Tailscale and [t3code](https://github.com/pingdotgg/t3code).

This setup lets you leave the computing power at home or on a server and connect from a lightweight remote device. The host machine stays on, runs your coding agents, and is intended to be accessed from devices on your private Tailscale network.

## Quick Start

On the computer or server you want to access remotely:

Prerequisites:
- macOS: ability to install the standalone [Tailscale for macOS](https://tailscale.com/download/mac) app and complete its sign-in flow locally
- Linux: `systemd`, `sudo`, and `curl`
- [Node.js](https://nodejs.org) 22.16+, 23.11+, or 24.10+ installed
- At least one supported coding-agent CLI installed: [Claude Code](https://code.claude.com/docs/en/overview#get-started) or [Codex CLI](https://developers.openai.com/codex/cli)

```bash
curl -fsSL https://raw.githubusercontent.com/nathangathright/tailscale-t3code-setup/main/setup.sh | bash
```

What happens during setup:
- On macOS, the script opens the official Tailscale download page. Install the standalone app, launch it, and finish the Tailscale onboarding flow on that Mac.
- On Linux, the script installs Tailscale with the official installer, enables `tailscaled` with `systemd`, and continues automatically.
- On both platforms, the script installs `t3code`, configures it to start automatically, and prints the Tailscale hostname at the end.

On your remote device, install Tailscale, sign in to the same tailnet, then open `http://<tailscale-hostname>:3773` in a browser to start coding.

## What the Script Does

- Installs Tailscale for encrypted networking between devices
- Installs [t3code](https://github.com/pingdotgg/t3code), a web GUI for AI coding agents (Claude and Codex), as a background service on port 3773
- Uses the recommended standalone Tailscale app flow on macOS and the official install script on Linux
- Uses `launchd` on macOS and `systemd` on Linux servers
- Installs the [tailserve](https://github.com/nathangathright/tailserve) skill into your detected coding agent CLIs so they know how to preview web projects over Tailscale

Tailscale encrypts traffic end-to-end. In the default workflow, you access t3code from devices on your private Tailscale network.

## Platform Notes

macOS:
- The script expects the standalone Tailscale app, not a Homebrew install.
- If you already have a Homebrew-installed `tailscale` CLI, the script will still require the standalone app in `/Applications/Tailscale.app`.
- The Tailscale sign-in step is interactive and must be completed on the Mac running the script.
- `t3code` is installed as a user `launchd` service.

Linux:
- The script expects a `systemd`-based machine.
- Tailscale is installed with `https://tailscale.com/install.sh`.
- `t3code` is installed as a system `systemd` service for the current user.

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

macOS:

```bash
launchctl bootout gui/$(id -u)/com.t3code.server
rm ~/Library/LaunchAgents/com.t3code.server.plist
npm uninstall -g t3
npx skills remove --global --agent '*' tailserve -y
```

Then remove the Tailscale app from `/Applications` if you want to fully uninstall it.

Linux:

```bash
sudo systemctl disable --now t3code-$(id -un).service
sudo rm /etc/systemd/system/t3code-$(id -un).service
sudo systemctl daemon-reload
npm uninstall -g t3
sudo systemctl disable --now tailscaled
npx skills remove --global --agent '*' tailserve -y
```

Then remove the `tailscale` package with your distro's package manager if you want to fully uninstall it.

## License

MIT
