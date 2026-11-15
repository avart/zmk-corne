#!/usr/bin/env bash
# Build and flash the left half of the Corne Choc Pro.
#
#   flash-left.sh                 build, then flash nice_view-corne_choc_pro_left-zmk.uf2
#   flash-left.sh --no-build      flash the existing file without building
#   flash-left.sh --settings-reset   flash settings_reset-corne_choc_pro_left-zmk.uf2
#
# Waits for the UF2 bootloader volume (/Volumes/KEEBART) to appear after the user
# presses reset, copies the firmware, and treats the volume unmounting as success.
set -euo pipefail

VOLUME="${KEEB_VOLUME:-/Volumes/KEEBART}"
MOUNT_TIMEOUT="${MOUNT_TIMEOUT:-300}"   # seconds to wait for the user to press reset
UNMOUNT_TIMEOUT="${UNMOUNT_TIMEOUT:-60}" # seconds to wait for the flash to finish

repo="$(cd "$(dirname "$0")/../../.." && pwd)"
target="nice_view-corne_choc_pro_left-zmk"
build=1
for arg in "$@"; do
    case "$arg" in
        --no-build) build=0 ;;
        --settings-reset) target="settings_reset-corne_choc_pro_left-zmk" ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
fw="$repo/firmware/$target.uf2"

if [ "$build" = 1 ]; then
    echo ">> Building $target"
    log="${TMPDIR:-/tmp}/flash-left-build.log"
    if ! "$repo/build.sh" "$target" >"$log" 2>&1; then
        tail -n 40 "$log" >&2
        echo "BUILD FAILED (full log: $log)" >&2
        exit 1
    fi
    tail -n 1 "$log"
fi
[ -f "$fw" ] || { echo "Missing $fw - build it first" >&2; exit 1; }

if [ ! -d "$VOLUME" ]; then
    echo ">> Waiting up to ${MOUNT_TIMEOUT}s for $VOLUME (connect the left half and press reset)"
    waited=0
    until [ -d "$VOLUME" ]; do
        if [ "$waited" -ge "$MOUNT_TIMEOUT" ]; then
            echo "TIMEOUT: $VOLUME never appeared" >&2
            exit 3
        fi
        sleep 1
        waited=$((waited + 1))
    done
    sleep 2 # let the mount settle before writing
fi

if [ ! -f "$VOLUME/INFO_UF2.TXT" ]; then
    echo "$VOLUME has no INFO_UF2.TXT - not a UF2 bootloader, refusing to copy" >&2
    exit 4
fi

echo ">> Copying $(basename "$fw") to $VOLUME"
# -X: no extended attributes (no ._ files). The bootloader reboots as soon as it
# has the image, so cp may report an I/O error even though the flash worked; the
# unmount below is the real success signal.
cp -X "$fw" "$VOLUME/" || echo "(cp exited with $? - checking for unmount)"

waited=0
while [ -d "$VOLUME" ]; do
    if [ "$waited" -ge "$UNMOUNT_TIMEOUT" ]; then
        echo "FAILED: $VOLUME still mounted after ${UNMOUNT_TIMEOUT}s" >&2
        exit 5
    fi
    sleep 1
    waited=$((waited + 1))
done
echo "OK: $VOLUME unmounted - left half flashed with $(basename "$fw")"
