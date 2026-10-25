# Shared setup for the commands ios/scripts/mac.sh runs on the Mac. mac.sh sends this file over
# SSH ahead of each command, after setting REPO. Not meant to be run on its own.

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
if [ -f "$HOME/.config/starwire/env" ]; then
    . "$HOME/.config/starwire/env"
fi
if [ -d "$REPO" ]; then
    cd "$REPO"
    mkdir -p build/runs
fi

need_team() {
    if [ -z "${STARWIRE_TEAM:-}" ]; then
        echo "STARWIRE_TEAM isn't set: put it in ~/.config/starwire/env on the Mac (runbook section 3)" >&2
        exit 2
    fi
}

# The iPad to use. STARWIRE_DEVICE (passed from the PC by mac.sh) names one by UDID. Without it,
# the only physical iPad connected is used, or IPAD from the env file. With more than one iPad
# connected and no STARWIRE_DEVICE, it stops: an iPad that is in someone else's use must never be
# picked by accident.
need_ipad() {
    local list ipads count
    list=$(xcrun devicectl list devices 2>/dev/null || true)
    ipads=$(echo "$list" | awk '/iPad/ && / physical/ && !/unavailable/ {
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i }')
    count=$(echo "$ipads" | grep -c . || true)
    if [ -n "${STARWIRE_DEVICE:-}" ]; then
        if ! echo "$ipads" | grep -qx "$STARWIRE_DEVICE"; then
            echo "STARWIRE_DEVICE $STARWIRE_DEVICE isn't connected and available:" >&2
            echo "$list" >&2
            exit 3
        fi
        IPAD=$STARWIRE_DEVICE
    elif [ "$count" -gt 1 ]; then
        echo "$count iPads are connected. Name one with STARWIRE_DEVICE=<UDID> (on the PC, or in" >&2
        echo "~/.config/starwire/device there); mac.sh won't pick one itself:" >&2
        echo "$list" | grep -E "iPad.* physical" >&2
        exit 3
    elif [ -z "${IPAD:-}" ]; then
        IPAD=$ipads
    fi
    if [ -z "${IPAD:-}" ]; then
        echo "No iPad is connected to the Mac (xcrun devicectl list devices). Plug it in, unlocked." >&2
        echo "$list" >&2
        exit 3
    fi
    echo "device: $(echo "$list" | grep "$IPAD" | sed -E 's/ {2,}/ | /g' | cut -c1-120)" >&2
}

# Runs a command line in the logged-in user's GUI session and waits for it, up to an hour.
# Signing needs the login keychain, which macOS keeps locked to SSH sessions (codesign fails with
# errSecInternalComponent). A one-off launchd job in the GUI session can use it, as self-hosted
# CI runners do. The job is removed when it ends. Its output goes to build/gui-job.log, printed
# at the end, and its exit status is returned.
in_gui() {
    local label=io.github.shev0k.starwire.job
    local dir="$PWD/build"
    {
        echo '#!/bin/bash'
        echo "cd '$PWD'"
        echo 'export PATH="$HOME/.local/bin:$PATH"'
        echo "exec > '$dir/gui-job.log' 2>&1"
        echo "( $1 )"
        echo "echo \$? > '$dir/gui-job.done'"
    } > "$dir/gui-job.sh"
    cat > "$dir/gui-job.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$dir/gui-job.sh</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
    rm -f "$dir/gui-job.done" "$dir/gui-job.log"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$dir/gui-job.plist"
    local waited=0
    while [ ! -f "$dir/gui-job.done" ] && [ "$waited" -lt 3600 ]; do
        sleep 5
        waited=$((waited + 5))
    done
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    cat "$dir/gui-job.log" 2>/dev/null || true
    if [ ! -f "$dir/gui-job.done" ]; then
        echo "the GUI job didn't finish within an hour" >&2
        return 6
    fi
    return "$(cat "$dir/gui-job.done")"
}
