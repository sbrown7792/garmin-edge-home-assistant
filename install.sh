#!/usr/bin/env bash
# ./install.sh [app|widget|field|both]  copies built variants onto a USB-connected Edge.
# Uses gio over MTP — the gvfs FUSE path is often empty even when the device is
# mounted, so copying through the mtp:// URI is the reliable route.
set -euo pipefail

VARIANT="${1:-both}"

case "$VARIANT" in
    app)    OUTPUTS=(bin/HaControl.prg) ;;
    widget) OUTPUTS=(bin/HaControlWidget.prg) ;;
    field)  OUTPUTS=(bin/HaArrival.prg) ;;
    both)   OUTPUTS=(bin/HaControl.prg bin/HaArrival.prg) ;;
    *)      echo "Usage: $0 [app|widget|field|both]" >&2; exit 1 ;;
esac

URI="$(gio mount -li | grep -oE 'mtp://[A-Za-z0-9_%.-]+/' | head -1)"
if [ -z "$URI" ]; then
    echo "No MTP device found. Plug in the Edge, unlock it, and accept any" >&2
    echo "'allow access' prompt on the device." >&2
    exit 1
fi

STORAGE="$(gio list "$URI" | head -1)"
APPS="$URI$STORAGE/Garmin/Apps"

for out in "${OUTPUTS[@]}"; do
    if [ ! -f "$out" ]; then
        echo "$out not built yet — run ./build.sh first." >&2
        exit 1
    fi
    gio copy "$out" "$APPS/"
    echo "Copied $out to $APPS"
done

# Connect IQ only writes a sideloaded app's println output if a log file with the app's
# name already exists, so create an empty one for the data field's ride log.
case "$VARIANT" in
    field|both)
        LOG="$URI$STORAGE/Garmin/Apps/LOGS/HaArrival.TXT"
        if ! gio info "$LOG" >/dev/null 2>&1; then
            EMPTY="$(mktemp)"
            gio copy "$EMPTY" "$LOG"
            rm -f "$EMPTY"
            echo "Created $LOG"
        fi
        ;;
esac

echo "Eject the Edge and restart it before looking for the app."
