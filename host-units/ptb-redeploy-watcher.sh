#!/bin/sh
# Processes trigger files dropped by ptb-manager (running inside a container
# that cannot reach this systemd --user bus directly - see
# ptb-manager.container and bot/triggers.py) into real `systemctl --user`
# actions run natively on the host.
#
# Deliberately does NOT execute file *content* as commands - only the
# filename drives the action, and every unit/project name is validated
# against a strict character set AND checked to actually exist before
# anything runs, so a compromised bot process can at most restart/start one
# of its own already-installed fleet units, not run arbitrary code.
set -eu

TRIGGER_DIR="$HOME/projects/.triggers"
QUADLETS_DIR="$HOME/.config/containers/systemd"

[ -d "$TRIGGER_DIR" ] || exit 0

is_valid_name() {
    case "$1" in
        ""|*[!a-zA-Z0-9_-]*) return 1 ;;
        *) return 0 ;;
    esac
}

for f in "$TRIGGER_DIR"/*.trigger; do
    [ -e "$f" ] || continue
    base=$(basename "$f")

    case "$base" in
        restart__*)
            rest=${base#restart__}
            name=${rest%%__*}
            if is_valid_name "$name" && systemctl --user list-unit-files "${name}.service" --no-legend 2>/dev/null | grep -q .; then
                logger -t ptb-redeploy-watcher "Restarting ${name}.service (trigger: $base)"
                systemctl --user restart "${name}.service" || logger -t ptb-redeploy-watcher "Restart failed for ${name}.service"
            else
                logger -t ptb-redeploy-watcher "Rejecting trigger (unknown/invalid unit): $base"
            fi
            ;;
        setup__*)
            rest=${base#setup__}
            name=${rest%%__*}
            if is_valid_name "$name" && [ -f "$QUADLETS_DIR/${name}.container" ]; then
                logger -t ptb-redeploy-watcher "Reloading and starting ${name}.service (trigger: $base)"
                systemctl --user daemon-reload || true
                systemctl --user start "${name}.service" || logger -t ptb-redeploy-watcher "Start failed for ${name}.service"
            else
                logger -t ptb-redeploy-watcher "Rejecting trigger (unknown/invalid project): $base"
            fi
            ;;
        reload__*)
            logger -t ptb-redeploy-watcher "Reloading systemd daemon (trigger: $base)"
            systemctl --user daemon-reload || logger -t ptb-redeploy-watcher "daemon-reload failed"
            ;;
        *)
            logger -t ptb-redeploy-watcher "Rejecting unrecognized trigger file: $base"
            ;;
    esac

    rm -f "$f"
done
