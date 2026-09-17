#!/usr/bin/env bash
# Builds, starts the Connect IQ simulator, and loads the app into it.
# The simulator needs the same webkit2gtk-4.0 compatibility libraries as the
# SDK Manager — see sdk-manager.sh for why.
set -euo pipefail

SDK_ROOT="${SDK_ROOT:-$HOME/.Garmin/ConnectIQ/Sdks}"
SDK="$(ls -d "$SDK_ROOT"/connectiq-sdk-lin-* 2>/dev/null | sort -V | tail -1)"
DEVICE="${DEVICE:-edge1040}"
ARCHLIB="$HOME/.Garmin/ConnectIQ/compat-libs/root/usr/lib/x86_64-linux-gnu"
if [ -d "$ARCHLIB" ]; then
    # Ubuntu 24.04 workaround; see sdk-manager.sh.
    export LD_LIBRARY_PATH="$ARCHLIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export WEBKIT_DISABLE_COMPOSITING_MODE=1
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
fi
VARIANT="${1:-app}"

case "$VARIANT" in
    app)    OUTPUT=bin/HaControl.prg ;;
    widget) OUTPUT=bin/HaControlWidget.prg ;;
    *)      echo "Usage: $0 [app|widget]" >&2; exit 1 ;;
esac


./build.sh "$VARIANT"

if ! pgrep -x simulator >/dev/null; then
    "$SDK/bin/simulator" >/dev/null 2>&1 &
    sleep 4
fi

"$SDK/bin/monkeydo" "$OUTPUT" "$DEVICE"
