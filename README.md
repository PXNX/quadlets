# quadlets

Podman Quadlet unit files (`*.container`, `*.volume`, `*.network`) defining how each bot/service in the fleet runs under `systemd --user`. These are the source of truth for how each service is configured (image, volumes, env files, restart policy) and are installed on the `nyx` host under `~/.config/containers/systemd`.

## Deployment

Production deployment happens on the `nyx` host, reachable via:

```
ssh nyx@mn
```

Deployment there is orchestrated by two pieces working together:

- **This repo (`quadlets`)** — defines *how* each service runs (image, volumes, env files, restart policy, networking).
- **[`ptb-manager`](../ptb-manager)** — a Telegram bot running on `nyx` that acts as the operator console for the fleet: it syncs a project's repo (`gh repo sync`), restarts the corresponding `systemd --user` service, tails/downloads container logs, backs up the Postgres databases, and can add/redeploy new quadlet-based projects.

In short: pushing to a project's repo doesn't deploy it by itself — someone (or an automation) needs to trigger `ptb-manager` (e.g. via its `/redeploy` command) or manually run the commands below on `nyx` for the change to go live.

## Useful commands

```sh
# Where quadlet unit files live on the host
~/.config/containers/systemd

# Pull the latest quadlet definitions from GitHub
gh repo sync

# Re-read unit files after adding/changing a quadlet
systemctl --user daemon-reload

# Check which tg-nn-related units are known to systemd
systemctl --user list-unit-files | grep tg-nn

# Validate a quadlet file without installing it
/usr/libexec/podman/quadlet --user --dryrun
```
