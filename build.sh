#!/usr/bin/env bash
# ./build.sh           builds the watch-app variant with your personal config
# ./build.sh widget    builds the widget variant (does not work on Edge x40 — see README)
# ./build.sh release   builds bin/HaControl.iq for the Connect IQ store, using the blank
#                      config in config/release so no personal data ships
# ./build.sh field     builds the HA Arrival data field (opens the garage on STOP at home)
# ./build.sh field-release   store package of the data field
set -euo pipefail

SDK_ROOT="${SDK_ROOT:-$HOME/.Garmin/ConnectIQ/Sdks}"
SDK="$(ls -d "$SDK_ROOT"/connectiq-sdk-lin-* 2>/dev/null | sort -V | tail -1)"
DEVICE="${DEVICE:-edge1040}"
VARIANT="${1:-app}"

case "$VARIANT" in
    app)     JUNGLE=monkey.jungle;  OUTPUT=bin/HaControl.prg ;;
    widget)  JUNGLE=widget.jungle;  OUTPUT=bin/HaControlWidget.prg ;;
    release) JUNGLE=release.jungle; OUTPUT=bin/HaControl.iq ;;
    field)   JUNGLE=field.jungle;   OUTPUT=bin/HaArrival.prg ;;
    field-release) JUNGLE=field-release.jungle; OUTPUT=bin/HaArrival.iq ;;
    *)       echo "Usage: $0 [app|widget|release|field|field-release]" >&2; exit 1 ;;
esac

if [ -z "$SDK" ]; then
    echo "No Connect IQ SDK found under $SDK_ROOT" >&2
    exit 1
fi

if [ ! -f developer_key.der ]; then
    echo "No developer_key.der. Generate your own signing key once, and keep it:" >&2
    echo "  openssl genrsa -out developer_key.pem 4096" >&2
    echo "  openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt" >&2
    exit 1
fi

case "$VARIANT" in
    app|widget|field)
        if [ ! -f config/personal/Config.mc ]; then
            echo "No config/personal/Config.mc. Start from the blank template and fill it in:" >&2
            echo "  mkdir -p config/personal && cp config/release/Config.mc config/personal/" >&2
            exit 1
        fi
        ;;
esac

if [ ! -d "$HOME/.Garmin/ConnectIQ/Devices/$DEVICE" ]; then
    echo "Device package '$DEVICE' is not installed." >&2
    echo "Run ./sdk-manager.sh, sign in with your Garmin account, and download Edge 1040." >&2
    exit 1
fi

mkdir -p bin

if [ "$VARIANT" = "release" ] || [ "$VARIANT" = "field-release" ]; then
    # -e packages every product in the manifest into one .iq for the store; -r strips
    # debug information.
    "$SDK/bin/monkeyc" \
        --jungles "$JUNGLE" \
        --private-key developer_key.der \
        --output "$OUTPUT" \
        --package-app \
        --release \
        --warn
    echo "Built $OUTPUT"
    exit 0
fi

"$SDK/bin/monkeyc" \
    --jungles "$JUNGLE" \
    --device "$DEVICE" \
    --private-key developer_key.der \
    --output "$OUTPUT" \
    --warn

echo "Built $OUTPUT"
