# gate-x

Licensed OpenAI- and Anthropic-compatible CLI proxy. Buy a key from the bot,
activate it on up to **2 devices**, and run `gate-x serve`.

This repository ships the **compiled** build only. Source lives elsewhere.

## Install

Requires **Python 3.12** on Linux x86_64.

```bash
pip install "https://github.com/MADE-ADI/gate-x-cli/releases/latest/download/gate_x-0.1.0-cp312-cp312-manylinux_2_35_x86_64.whl"
```

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

## Manage this machine

```bash
gate-x license status        # plan, expiry, device
gate-x license devices       # machines bound to your key
gate-x license deactivate    # free this slot to move to another machine
```

## Notes

- One key runs on at most two machines. Free a slot with `deactivate` (once per
  30 days self-service) or from the bot's `/devices`.
- The build is locked to Python 3.12. Use a matching interpreter or a venv:
  `python3.12 -m venv .venv && .venv/bin/pip install gate_x-*.whl`.

Support: through the Telegram bot you bought your key from.
