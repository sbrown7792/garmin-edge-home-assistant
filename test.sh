#!/usr/bin/env bash
# Runs the data field's unit tests in the Connect IQ simulator. No input is simulated;
# results are printed here.
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
OUTPUT=bin/HaArrival-test.prg


mkdir -p bin
"$SDK/bin/monkeyc" --jungles field.jungle --device "$DEVICE" \
    --private-key developer_key.der --output "$OUTPUT" --unit-test

if ! pgrep -x simulator >/dev/null; then
    "$SDK/bin/simulator" >/dev/null 2>&1 &
    sleep 6
fi

"$SDK/bin/monkeydo" "$OUTPUT" "$DEVICE" -t
