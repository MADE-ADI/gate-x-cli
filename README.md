# gate-x

Licensed OpenAI- and Anthropic-compatible CLI proxy. Buy a key from
[**@sekai_gatex_bot**](https://t.me/sekai_gatex_bot), activate it on up to
**2 devices**, and run `gate-x serve`.

## Buy a licence

Licences are sold only through the Telegram bot:

### 👉 [t.me/sekai_gatex_bot](https://t.me/sekai_gatex_bot)

Open it, pick a plan, pay, and the bot sends you a key that looks like
`GATEX-XXXX-XXXX-XXXX-XXXX`. The same bot handles renewals, extra devices and
support. Anyone selling gate-x keys anywhere else is not us.

This repository ships the **compiled** build only. Source lives elsewhere.

## Install (one command)

Checks for Python 3.12 (installs it if missing), builds an isolated venv,
installs the compiled build, and verifies it runs:

```bash
curl -fsSL https://raw.githubusercontent.com/SEKAI-MIRROR/gate-x-cli/main/bootstrap.sh | bash -s -- --dir gate-x
```

Pass your key to activate in the same step:

```bash
curl -fsSL https://raw.githubusercontent.com/SEKAI-MIRROR/gate-x-cli/main/bootstrap.sh | bash -s -- --server https://YOUR-LICENSE-SERVER --key GATEX-XXXX-XXXX-XXXX-XXXX
```

## Install (manual)

Requires **Python 3.12** on Linux x86_64.

```bash
pip install "$(curl -fsSL https://api.github.com/repos/SEKAI-MIRROR/gate-x-cli/releases/latest | grep -oE 'https://[^"]+cp312[^"]+\.whl')"
```

The wheel filename embeds the version (`gate_x-0.1.1-cp312-...`), so don't
pin `releases/latest/download/<filename>` directly — that literal name stops
existing the moment a new version ships. Resolve the URL from the API, as above.

or grab the wheel from the [latest release](../../releases/latest) and:

```bash
pip install ./gate_x-*.whl
```

## Activate

```bash
gate-x license activate GATEX-XXXX-XXXX-XXXX-XXXX --server https://YOUR-LICENSE-SERVER
```

Then create a `config.yaml`:

```yaml
host: 127.0.0.1
port: 8317
auth-dir: ""            # broker mode leases credentials; keep this empty
api-keys:
  - your-local-api-key
plugins:
  enabled: true
  configs:
    license:
      server: https://YOUR-LICENSE-SERVER
      broker: true
      enforce: true
```

Run it:

```bash
gate-x -c config.yaml serve
```

Point any OpenAI or Anthropic SDK at `http://127.0.0.1:8317`.

## Updates

```bash
gate-x update            # check only
gate-x update --apply    # download + install the newer release
```

**Manual update (one command):** finds your install, backs up your credentials
(`~/.gate-x`) and `config.yaml` to `~/gate-x-backup-<timestamp>.tar.gz`,
installs the newest release, refreshes the systemd units and restarts the
service. Nothing you logged in or configured is touched:

```bash
curl -fsSL https://raw.githubusercontent.com/SEKAI-MIRROR/gate-x-cli/main/update.sh | bash -s -- --dir gate-x
```

Options: `--dir DIR` (install location, default `./gate-x` then `~/gate-x`),
`--repo owner/name` (release repo), `--no-backup`. Safe to re-run; it also
works on an old build that has no `gate-x update` command yet.

**Fully automatic (no manual update needed):** run this once after install to
put gate-x under systemd `--user` and have it check for updates every 5
minutes, auto-installing and restarting itself when a new release ships:

```bash
curl -fsSL https://raw.githubusercontent.com/SEKAI-MIRROR/gate-x-cli/main/install-service.sh | bash -s -- --dir gate-x
```

Change the cadence with `--interval SECONDS` (default 300). Check on it any time:

```bash
systemctl --user status gatex.service gatex-update.timer
journalctl --user -u gatex-update.service -f
```

Note: a machine installed **before** this existed (v0.1.0) has no `update`
command — run `update.sh` above (or the manual install command) once to get
onto a version that has it, then `install-service.sh` works as usual.

## Uninstall

```bash
gate-x uninstall            # stops the service, frees the license slot, removes everything
```

## Manage this machine

```bash
gate-x license status        # plan, expiry, device
gate-x license devices       # machines bound to your key
gate-x license deactivate    # free this slot to move to another machine
```

## Notes

- One key runs on at most two machines. Free a slot with `deactivate` (once per
  30 days self-service) or from [@sekai_gatex_bot](https://t.me/sekai_gatex_bot)'s `/devices`.
- The build is locked to Python 3.12. Use a matching interpreter or a venv:
  `python3.12 -m venv .venv && .venv/bin/pip install gate_x-*.whl`.

Support and renewals: [@sekai_gatex_bot](https://t.me/sekai_gatex_bot).
