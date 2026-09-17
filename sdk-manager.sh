#!/usr/bin/env bash
# Launches Garmin's SDK Manager. Sign in with a Garmin account once to download
# the Edge 1040 device package that the compiler and simulator need.
#
# The SDK Manager links libsoup2 and needs webkit2gtk-4.0, which Ubuntu 24.04 no
# longer ships (24.04 has webkit2gtk-4.1, built on libsoup3 — mixing the two
# aborts the process). Debian bookworm's webkit2gtk-4.0 and its dependencies are
# unpacked under compat-libs and used only by this process.
set -euo pipefail

COMPAT="$HOME/.Garmin/ConnectIQ/compat-libs/root"
ARCHLIB="$COMPAT/usr/lib/x86_64-linux-gnu"

# Only where the compatibility libraries have been set up; elsewhere the system's own
# webkit2gtk-4.0 is used, as Garmin intends.
if [ -d "$ARCHLIB" ]; then
    export LD_LIBRARY_PATH="$ARCHLIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export WEBKIT_DISABLE_COMPOSITING_MODE=1
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
fi

MANAGER="${SDK_MANAGER:-$HOME/.Garmin/ConnectIQ/sdkmanager/bin/sdkmanager}"
if [ ! -x "$MANAGER" ]; then
    echo "SDK Manager not found at $MANAGER." >&2
    echo "Download it from https://developer.garmin.com/connect-iq/sdk/ and set SDK_MANAGER." >&2
    exit 1
fi

exec "$MANAGER" "$@"
