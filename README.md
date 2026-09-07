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

## Redeploy watcher (`host-units/`)

`systemctl --user` cannot be called directly from inside the `ptb-manager` container - its D-Bus `EXTERNAL` auth handshake against the bind-mounted host session bus fails (confirmed even after dropping privileges to the host's own uid; root cause not fully understood, but reliably reproducible). So `ptb-manager` can't restart itself or other services by calling `systemctl` in-container.

`host-units/` holds a small native (non-containerized) systemd --user path + service unit that runs directly on `nyx` as the `nyx` user, sidestepping the problem entirely: `ptb-manager` drops an empty, carefully-named trigger file into `~/projects/.triggers/`, the path unit notices the directory going from empty to non-empty, and the service unit's script (`ptb-redeploy-watcher.sh`) validates the filename against a strict allowlist (must match `^[a-zA-Z0-9_-]+$` *and* correspond to a real, already-installed unit/quadlet) before running the actual `systemctl --user restart/start/daemon-reload`. The script never executes file *content* - only the filename drives the action - so this isn't an arbitrary-command channel from the container into the host.

Unlike the `.container`/`.volume`/`.network` files above, these are **plain systemd unit files** and must live in the standard user unit search path (`~/.config/systemd/user/`), not `~/.config/containers/systemd` (which only the podman quadlet generator scans). One-time setup on `nyx`:

```sh
mkdir -p ~/.config/systemd/user
ln -sf ~/.config/containers/systemd/host-units/ptb-redeploy-watcher.path ~/.config/systemd/user/
ln -sf ~/.config/containers/systemd/host-units/ptb-redeploy-watcher.service ~/.config/systemd/user/
cp ~/.config/containers/systemd/host-units/ptb-redeploy-watcher.sh ~/.config/systemd/user/
chmod +x ~/.config/systemd/user/ptb-redeploy-watcher.sh
systemctl --user daemon-reload
systemctl --user enable --now ptb-redeploy-watcher.path
```

The `.sh` is `cp`'d rather than symlinked since it's executed directly by path, and re-running `cp` after a `gh repo sync` picks up script changes (the `.path`/`.service` symlinks never need touching again).

