# AGENTS.md

Notes for coding agents that build, deploy or change this repository on someone's behalf.
[README.md](README.md) is the human guide and explains the why at length. This file
collects the rules, commands and traps that cost real time during development.

The repository builds two Connect IQ apps for Garmin Edge bike computers:

- **HA Control** (`source/`, a watch-app with a glance) — buttons that fire Home
  Assistant events.
- **HA Arrival** (`field/`, a data field) — fires an event when the ride timer is
  stopped inside Home Assistant's home zone.

Both send `POST /api/events/<type>` with `{"action": "<label>"}`. Automations in Home
Assistant match on that label and do the actual work.

## Ground rules

- **Assume the actions move real hardware.** In the reference setup they open a garage
  door. Never fire a real action without the human's go-ahead at that moment. That
  covers a device button, the simulator and `curl` alike. **The simulator makes real web
  requests**, so a press there opens the real door.
- **Prove the path with Test ping instead.** It is an event with `"action": "Test ping"`.
  Home Assistant answers `200` to any event even when nothing listens, so it is always
  safe to send.
- **Keep the token secret.** The Home Assistant token lives in `config/personal/Config.mc`,
  which is gitignored, and is compiled into the `.prg` in readable form. Never print it,
  commit it, paste it into an issue, or copy a personal `.prg` anywhere public.
- **Never regenerate `developer_key.der` if it already exists.** A new key makes the
  device treat the app as a different install, and store updates must be signed with the
  original key.
- **Ask before changing Home Assistant.** Editing its configuration, creating
  automations or restarting it all need a yes first.
- **Do not drive the human's desktop.** No synthetic mouse or keyboard input into the
  simulator while they may be using the machine. No full-screen captures either, since
  those record whatever else is open. Capture only the simulator window, or ask the
  human to look.
- **Stay out of the network setup.** Getting Home Assistant onto HTTPS and reachable
  from the phone is the human's infrastructure, not part of this repository. If the
  checks below fail, report what failed and let them fix it.

## What only the human can do

Plan around these, and ask for them explicitly rather than guessing:

- **SDK Manager.** Sign in to Garmin's SDK Manager (`./sdk-manager.sh`) and download the
  SDK plus a device package for each target.
- **Access token.** Create a Home Assistant long-lived access token under Profile >
  Security, ideally one used only by the Edge.
- **Installing.** Plug in the Edge, unlock it, and accept any access prompt. After
  `install.sh`, eject it and restart it.
- **Testing on the device.** The Edge cannot run apps while mounted over USB, so real
  tests happen unplugged. Ask the human to report exactly what the screen shows,
  including any error code.
- **Phone.** Keep the Garmin Connect app paired and running. If Home Assistant is only on
  the LAN, the phone's VPN must be up.
- **Store listing.** Submit at apps.garmin.com.

## Commands

| Command | Does |
| --- | --- |
| `./build.sh` | HA Control → `bin/HaControl.prg` (personal config) |
| `./build.sh field` | HA Arrival → `bin/HaArrival.prg` (personal config) |
| `./build.sh release` / `field-release` | Store packages `bin/HaControl.iq` / `bin/HaArrival.iq` (blank config) |
| `./build.sh widget` | Widget variant, which does not appear on an Edge x40 (see below) |
| `./install.sh app\|field\|both` | Copies `.prg` files to a USB-connected Edge |
| `./test.sh` | HA Arrival unit tests in the simulator |
| `./simulate.sh` | Builds HA Control and runs it in the simulator |
| `python3 tools/read_ride_log.py ride.fit` | Prints HA Arrival's diagnostics from a ride (`pip install fitdecode`) |

The scripts also read these environment variables:

- `DEVICE` — the target product, default `edge1040`.
- `SDK_ROOT` — where the SDKs live, default `~/.Garmin/ConnectIQ/Sdks`.
- `SDK_MANAGER` — the SDK Manager binary.

`build.sh` stops with the exact fix when the SDK, device package, signing key or personal
config is missing. First-time setup is in the README's *Getting started*.

## How configuration is wired

- **The jungle picks the config.** `monkey.jungle` and `field.jungle` compile
  `config/personal/`, and the `*release.jungle` files compile the blank `config/release/`.
  Never put a `Config.mc` in `source/`, `field/` or `shared/`: it would ship in store
  builds or collide with the other one.
- **Settings override the compiled values.** `shared/AppConfig.mc` uses a Garmin Connect
  setting when it is non-empty and falls back to the `Config.mc` constant otherwise.
- **Sideloaded apps never show a settings screen,** so `Config.mc` is the only
  configuration for a `.prg` copied over USB.
- **Stored properties survive reinstalls.** Changing a default in `properties.xml` does
  not reach a device that already has the app.
- **Use `:event` for every action.** Keep `:service` and `:webhook` out of new
  configurations for the reason under *The phone relay*.

## Check Home Assistant before touching the Edge

Keep the token in a file outside the repository with mode `600`, and never echo it:

```bash
HA=https://ha.example.com
TOKEN_FILE=~/.config/ha-edge/token

# Expect {"message":"API running."}
curl -sS -H "Authorization: Bearer $(cat "$TOKEN_FILE")" "$HA/api/"

# Safe: expect {"message":"Event garmin_edge fired."}
curl -sS -X POST -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
  -H "Content-Type: application/json" -d '{"action":"Test ping"}' \
  "$HA/api/events/garmin_edge"
```

Run these **without `-k`**. The phone accepts only a publicly trusted certificate, and
Android ignores user-installed CAs for Garmin Connect. If `curl` needs `-k`, the Edge
will fail too.

The package in `homeassistant/garmin_ha_control.yaml` counts Test ping presses in
`counter.garmin_test_presses`, so reading that counter's state before and after a press
confirms delivery.

## Gotchas

### The phone relay

- **The Edge never goes online itself.** `makeWebRequest` travels over Bluetooth to the
  Garmin Connect app, which makes the request and validates the certificate. The Home
  Assistant companion app plays no part.
- **The relay can reject a reply after the request has already worked.** It parses
  replies by the server's `Content-Type`, and two of Home Assistant's replies defeat it:
  - `/api/webhook` returns an empty body with no `Content-Type`.
  - `/api/services` returns a top-level JSON array.

  Both reach the app as **`-400`** even though the action ran. `/api/events` returns a
  small JSON object, which gets through. On a real device, **`-400` means the request
  succeeded.**
- **The simulator is more lenient than the relay** and reports success for all three
  endpoints. Only a real device proves the reply path.
- **The relay sometimes never answers.** `ActionRunner` has a 20 s watchdog so the
  screen does not sit on SENDING forever. Keep a watchdog on any new request.
- **Connect IQ's own error codes are negative,** running from -1 into the -1000s. The
  field's private codes are -9001 to -9003 for that reason. Keep any new ones clear of
  that range.

### Home Assistant

- **A `400 Bad Request` on every request** usually means a reverse proxy that Home
  Assistant does not trust. That is network setup, so hand it to the human.
- **Automations match on the button label.** Renaming a button breaks its automation
  until the automation is updated too.
- **The arrival automation must only open.** Use `cover.open_cover` with a `state:
  closed` condition, never `cover.toggle`. A toggle on STOP shuts an open door, and an
  open command during travel reverses some openers.
- **Automations can be created over the API,** with the human's approval.
  - `POST /api/config/automation/config/<id>` is the endpoint the UI editor uses. It
    writes `automations.yaml` and reloads.
  - Helpers are created over the websocket with `input_boolean/create` and
    `counter/create`.
  - Alternatively, drop the package file into `packages/` and restart.

### Monkey C and the SDK

- **`makeWebRequest` rejects `Dictionary<String, String>`** for the body and headers.
  Build them as `Dictionary<Object, Object>`.
- **`x instanceof Numeric` does not compile,** because `Numeric` is a type alias rather
  than a class. Test `Number`, `Float`, `Double` and `Long` separately; see `isNumber()`
  in `field/HomeField.mc`.
- **A data field's `compute()` return type must say `Time.Duration`,** not a bare
  `Duration`.
- **A method named like an option symbol triggers a warning.** A `responseType()`
  method next to `:responseType`, for example, trips the name-collision check. Rename
  the method.
- **Everything the glance touches needs `(:glance)`,** and glance memory is tight.
  `AppConfig`, `StateReader` and `HaGlanceView` carry the annotation. A new dependency
  of the glance needs it too.
- **Each app has exactly one type.** Only data fields receive timer callbacks, and data
  fields take no button input. That is why there are two apps.
- **Keep decisions testable.** Logic lives in pure functions (`field/ArrivalRules.mc`)
  with `(:test)` functions beside them (`field/ArrivalRulesTest.mc`), and `./test.sh`
  runs them. Add a test for any new rule.
- **A store package needs every device.** `./build.sh release` builds every product in
  the manifest, so each one's device package must be installed.
- **Layouts must scale.** Size everything from `dc.getWidth()` and `dc.getHeight()`,
  because screens range from 240×320 to 480×800. Center text vertically with
  `TEXT_JUSTIFY_VCENTER` at the element's middle, not at its top.

### The Edge

- **The pull-down widget loop is closed to Connect IQ on the Edge x40 generation.**
  Tested on an Edge 1040, firmware 31.33. A widget build installs but never appears, so
  don't spend time retrying it. The home-screen glance is the replacement.
- **Install over MTP with `gio`** and the `mtp://` URI, which is what `install.sh` does.
  The gvfs FUSE mount often lists nothing.
- **The `.prg` disappears from `Garmin/Apps` after a restart.** The device absorbed it;
  the install did not fail.
- **The data field needs the right manifest permissions.**
  - Without **Positioning**, `Activity.Info.currentLocation` is always `null`, and
    nothing reports an error. The field just shows "No GPS".
  - `showAlert` needs **DataFieldAlert**.
  - Writing FIT fields needs **FitContributor**.
- **Timer buttons map to separate callbacks.** STOP calls `onTimerStop`, auto-pause
  calls `onTimerPause` and `onTimerResume`, and LAP calls `onTimerLap`. Only STOP should
  act.
- **FIT developer fields are tiny.**
  - A string field with a count of 48 or more fails with "New Field out of memory for
    FIT data".
  - Writing a string longer than `count - 1` crashes the app.
  - Keep per-second record fields numeric.
- **Logs stay on the device.**
  - `System.println` writes to `Garmin/Apps/LOGS/<PRG name>.TXT`, **but only if that
    file already exists**. `install.sh field` creates `HaArrival.TXT`.
  - Crash reports go to `CIQ_LOG.*` in the same folder.
- **Ride files are in `Garmin/Activities/`.** They contain a GPS track that usually
  starts and ends at the rider's home, so read them locally and never commit or upload
  them. `*.fit` is gitignored.

### The simulator on Linux

- **The simulator must be running before `monkeydo`.** The scripts start it and wait.
  If you get `Unable to connect to simulator`, wait a few seconds and rerun. If the
  simulator crashes on launch, start it again.
- **Ubuntu 24.04 lacks the webkit2gtk-4.0 the SDK tools need.** The workaround is in the
  README's *Linux notes*. The scripts use it automatically when
  `~/.Garmin/ConnectIQ/compat-libs` exists.
- **`./test.sh` prints its results in the terminal** and needs no input into the
  simulator.

## Publishing a fork to the store

1. **Give every manifest a new application ID.** The IDs in this repository belong to
   the existing listings, and the store rejects duplicates. Generate one per manifest
   with `python3 -c "import uuid; print(uuid.uuid4().hex)"`.
2. **Build with `./build.sh release` and `./build.sh field-release`.**
3. **Check that no personal data got in.** Before uploading, confirm that neither `.iq`
   contains the human's hostname or token, for example with
   `grep -ac "<their-host>" bin/*.iq`, which should print 0 for each file.
4. **Use the prepared listing text.** Listing and privacy text is in
   `store/listing.md`.

## Before committing

- **Never stage these:** `bin/`, `developer_key.*`, `config/personal/`, `*.fit`, or any
  other credentials.
- **Scan the staged diff.** Home Assistant long-lived tokens are JWTs beginning with
  `eyJ`. Run the check below and make sure the human's hostname, internal IP addresses
  and entity IDs are absent too.

  ```bash
  git diff --cached | grep -nE 'eyJ[A-Za-z0-9_-]{10,}|Bearer [A-Za-z0-9]'
  ```
- **Use placeholders in documentation and examples:** `ha.example.com` and
  `cover.garage_door`.
