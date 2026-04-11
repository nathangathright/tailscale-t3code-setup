# Remote Coding Setup with Tailscale and t3code

Set up a Mac or Linux machine for remote coding with Tailscale and [t3code](https://github.com/pingdotgg/t3code).

The script installs Tailscale, installs `t3code`, and runs it as a background service bound to the machine's Tailscale address. You connect to it from another device on the same tailnet.

## Quick Start

Run this on the machine you want to access remotely.

Prerequisites:
- macOS: ability to install the standalone [Tailscale for macOS](https://tailscale.com/download/mac) app and complete its sign-in flow locally
- Linux: `systemd`, `sudo`, and `curl`
- [Node.js](https://nodejs.org) 22.16+, 23.11+, or 24.10+ installed
- At least one supported coding-agent CLI installed: [Claude Code](https://code.claude.com/docs/en/overview#get-started) or [Codex CLI](https://developers.openai.com/codex/cli)

```bash
curl -fsSL https://raw.githubusercontent.com/nathangathright/tailscale-t3code-setup/main/setup.sh | bash
```

By default, the script uses port `3773`. To use a different port:

```bash
curl -fsSL https://raw.githubusercontent.com/nathangathright/tailscale-t3code-setup/main/setup.sh | T3_PORT=4000 bash
```

On macOS, the script opens the Tailscale download page and waits for you to finish the app install and sign-in flow. On Linux, it installs Tailscale automatically. On both platforms, it updates `t3code` to the latest npm release, sets up the background service, and prints the current pairing URL for your remote device when it can read it from the service logs.

On your remote device, install Tailscale, sign in to the same tailnet, then open the pairing URL printed by the script. It will look like `http://<tailscale-hostname>:3773/pair#token=...`. If the script cannot read the pairing URL automatically, open `http://<tailscale-hostname>:3773` and use the pairing URL shown in the service logs.

## Staying Up to Date

`t3code` is moving quickly. Re-running the setup script is the safest update routine because it refreshes both the script behavior and the installed `t3` CLI:

```bash
./setup.sh
```

If you used the one-line install from the README, re-run that same command. If you want to update the CLI first and then refresh the service definition:

```bash
npm install -g t3@latest
npx skills update
./setup.sh
```

To check whether an update is available before upgrading:

```bash
npm outdated -g t3
npx skills check
```

Re-running `setup.sh` matters because it refreshes the wrapper script, service definition, pairing flow, bind host, and PATH used by the background service.

## Previewing Web Projects

Because both devices are on the same Tailscale network, dev servers on your computer can also be reachable from your remote device.

The setup script installs the [tailserve](https://github.com/nathangathright/tailserve) skill so your coding agents know the right preview commands for common frameworks. Ask your agent to "preview this project over Tailscale" and it will know what to do.

`tailserve` covers two common approaches:
- **Direct tailnet access** — bind to `0.0.0.0`, access via `http://<hostname>:<port>`
- **`tailscale serve`** — automatic HTTPS, path-based routing for multiple projects

## Uninstalling

```bash
if [ "$(uname -s)" = "Darwin" ]; then
  launchctl bootout gui/$(id -u)/com.t3code.server
  rm ~/Library/LaunchAgents/com.t3code.server.plist
else
  sudo systemctl disable --now t3code-$(id -un).service
  sudo rm /etc/systemd/system/t3code-$(id -un).service
  sudo systemctl daemon-reload
fi

rm ~/.t3/run-t3code.sh
npm uninstall -g t3
npx skills remove --global --agent '*' tailserve -y
```

To remove Tailscale too, delete the macOS app from `/Applications` or uninstall the Linux package with your distro's package manager.

## License

MIT
