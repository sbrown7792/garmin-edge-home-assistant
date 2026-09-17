# HA Control — Home Assistant buttons on a Garmin Edge

Fires Home Assistant actions from an Edge 1040: open a garage, toggle a light, run a
script. The Edge has no internet radio for this — `Communications.makeWebRequest()` is
relayed over Bluetooth by the Garmin Connect app on your phone, and the phone's data
connection carries the request. The Home Assistant companion app is not involved.

One action goes straight to its button screen, which is also where tapping the glance
lands you. Two or more get a menu; picking an item opens that item's screen without
firing it, so the button on the screen stays the one deliberate press. **START** or a tap
sends.

### One button that both opens and closes

Give an action an `:entity` and the screen becomes a two-way control rather than a
fire-and-forget button:

```monkeyc
{ :label => "Garage", :event => "garmin_edge", :entity => "cover.garage_door" }
```

The screen reads that entity's live state and the button says what the press will do —
**OPEN** when the door is closed, **CLOSE** when it is open — above a door panel in the
same colours as the glance. The press fires the event; your automation does the toggling
(see section 2). After a press the screen re-reads the state twice, four seconds apart,
so a door that takes a while to travel still ends up showing the truth. Anything with a
meaningful state works: covers, lights, switches, `input_boolean`s.

Without an `:entity` the screen is a plain SEND button — right for a script, which has no
state worth showing.

Success and failure each play a single short beep — `SUCCESS_TONE` and `FAILURE_TONE` in
`Config.mc`, set to `TONE_LOUD_BEEP` and `TONE_ERROR`. Garmin's `TONE_SUCCESS` is the long
celebratory jingle, which wears thin on a button you press daily; `TONE_KEY` is the
quietest alternative.

## Getting started

You need the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/), installed and
kept current with Garmin's SDK Manager, plus the device packages for your Edge — the SDK
Manager downloads those after you sign in with a Garmin account. Java comes with most
setups already.

```bash
# A signing key, once. Keep it: a new key makes the device see a new app.
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem \
    -out developer_key.der -nocrypt

# Your configuration, from the blank template. Gitignored.
mkdir -p config/personal
cp config/release/Config.mc config/personal/
$EDITOR config/personal/Config.mc

./build.sh && ./install.sh app           # HA Control
./build.sh field && ./install.sh field   # HA Arrival
```

Then set up the Home Assistant side (section 2 below) and restart the Edge.

Layout:

| Path | Holds |
| --- | --- |
| `source/` | HA Control: glance, button screen, menu |
| `field/` | HA Arrival: the data field, its rules and unit tests |
| `shared/` | Settings resolution used by both apps |
| `config/release/` | Blank configuration for store builds, and the template for your own |
| `config/personal/` | Your configuration — gitignored |
| `resources/`, `resources-field/` | Strings, settings and icons for each app |
| `homeassistant/` | A package with every automation both apps expect |
| `store/` | Listing text for the Connect IQ store |
| `tools/` | `read_ride_log.py`, for reading HA Arrival's diagnostics out of a ride |

## Where the button lives on the Edge

**Tested on an Edge 1040, firmware 31.33: the swipe-down widget loop is not available to
Connect IQ apps.** A `type="widget"` build compiles and installs, but it never appears in
the loop and is not offered under System > Widgets > +. Connect IQ 4 removed widgets in
favour of glances, and this generation of Edge never got them back. The `widget.jungle` /
`manifest-widget.xml` pair is kept for other devices, but on an x40 it is a dead end.

What you get instead is the **home screen glance**: scroll the glances to *HA Control*
and tap it. It works while a ride is recording, and the glance itself shows live state
(see below). The app is also reachable from Menu > Connect IQ Apps.

If a button *in the pull-down loop* is non-negotiable, one route remains and it leaves
Connect IQ behind entirely: the native music controls widget is always in that loop, and
its buttons reach the phone as Android media-button events, which Tasker or MacroDroid
can catch and turn into a webhook call. It costs you your media controls while riding and
misfires if you listen to anything, so it is a last resort rather than a recommendation.

## Opening the garage automatically: HA Arrival

A second, separate app — a **data field** — opens the garage when you press **STOP**
within the radius of Home Assistant's home zone. It has to be a data field because only
data fields receive the activity timer callbacks, and Connect IQ apps are one type each.

```bash
./build.sh field && ./install.sh field
```

Then on the Edge: activity profile > Data Screens > pick a screen > add a field >
Connect IQ > **HA Arrival**. The field shows the distance home, and **STOP opens** once
you are inside the radius, so you know before you press.

**Only STOP acts.** Garmin reports each timer transition separately, and the field
listens to exactly one:

| Event | Effect |
| --- | --- |
| STOP (`onTimerStop`) | Opens the door if you are inside the radius |
| START (`onTimerStart`) | Nothing — it would reopen the door you just closed on the way out |
| Auto-pause (`onTimerPause` / `onTimerResume`) | Nothing — it fires at every traffic light |
| LAP (`onTimerLap`) | Nothing |

Further guards, each covered by a unit test (`./test.sh`):

- presses in the first 3 s after the field loads are ignored, so reopening an activity
  or switching profiles cannot fire the door by itself
- one command per minute, however many times STOP is pressed
- nothing fires without a GPS fix, or before the home location is known

**No coordinates to type in.** The field reads `zone.home` from Home Assistant — latitude,
longitude and radius — and caches it. The radius setting overrides the zone's if you want
a tighter trigger than the zone uses for presence.

It fires `garmin_edge` with `{"action": "Arrive", "trigger": "stop", "distance_m": …}`.
Pair it with an automation that **opens**, never toggles:

```yaml
alias: Garage open on arrival (Garmin Edge)
triggers:
  - trigger: event
    event_type: garmin_edge
    event_data:
      action: Arrive
conditions:
  - condition: state
    entity_id: cover.garage_door
    state: closed
actions:
  - action: cover.open_cover
    target:
      entity_id: cover.garage_door
mode: single
```

The `closed` condition matters: a toggle on STOP would shut a door that is already open,
and an open command on a door mid-travel can reverse it on some openers.

A success or failure pops a full-screen alert on the Edge, since the field may be on a
page you are not looking at when you stop.

The field needs the **Positioning** permission — without it `Activity.Info.currentLocation`
is always `null`, and the field sits at "No GPS" however good your fix is.

### Diagnosing a ride

The field logs as it goes, so a ride that misbehaves can be examined afterwards:

- **In the activity** — per-second developer fields: distance home, GPS / home / inside /
  enabled flags, GPS quality, an event counter with the latest event code, and the latest
  HTTP or Connect IQ response code. These also graph in Garmin Connect. The session
  summary holds the latest event line.
- **On the device** — the full narrative in `Garmin/Apps/LOGS/HaArrival.TXT`, which
  `install.sh field` creates, since Connect IQ only writes there if the file exists.

Save the ride, then with the Edge plugged in:

```bash
gio copy "mtp://<your-edge>/Internal Storage/Garmin/Activities/<ride>.fit" ride.fit
python3 tools/read_ride_log.py ride.fit      # needs: pip install fitdecode
```

It prints each event with the distance, flags and response code at that moment, then a
summary of GPS coverage. Timer events are logged even though only STOP acts, so the log
also confirms which callback each physical button produced on your device.

Garmin gives an app very little FIT space. A 48-byte string field fails to allocate, and
writing a string longer than its field crashes the app outright — so the FIT file carries
only the latest event line (32 bytes) and the text file carries everything.

## The glance shows live state

When `statusEntity` is set, the glance reads that entity from Home Assistant and draws a
door panel beside the name: filled and green when closed, empty and orange when open,
half and yellow while moving, grey when unknown or unreachable. The title comes from the
entity's `friendly_name`, so it matches what you see in Home Assistant. The last known
state is cached, so the glance renders instantly and then refreshes.

It works for anything with a meaningful state, not just covers — `off`/`locked` read as
closed, everything else as open.

## 1. Configure your actions

For a sideloaded build, configuration lives in `config/personal/Config.mc` (gitignored,
since it holds your token). The store build uses `config/release/Config.mc`, which is
blank, and takes everything from settings instead.

```monkeyc
const HA_BASE_URL = "https://ha.example.com";
const HA_TOKEN = "<long-lived access token>";
const STATUS_ENTITY = "cover.garage_door";     // what the glance shows
const EVENT_TYPE = "garmin_edge";

const ACTIONS = [
    { :label => "Garage", :event => "garmin_edge", :entity => "cover.garage_door" }
] as Array<Dictionary<Symbol, String>>;
```

Each action needs a `:label` and one of these. **Use `:event` for Home Assistant** — it is
the only one that reports its result honestly through a real Garmin device:

| Key | Sends | Result on a real device |
| --- | --- | --- |
| `:event` | POST `/api/events/<type>` with `{"action": "<label>"}`; needs the token and an automation | Works. The reply is a small JSON object. |
| `:service` | POST `/api/services/<domain>/<service>` with `:entity` as the target; needs the token | The call runs, but the screen shows **-400** |
| `:webhook` | POST `/api/webhook/<id>`; needs an automation, no token | The call runs, but the screen shows **-400** |
| `:url` | POST to any URL | Depends entirely on what that server replies |

**Why the other two fail.** The Garmin phone relay parses every reply according to the
server's own `Content-Type`, whatever the app asks for, and it cannot deliver either of
Home Assistant's answers: a webhook replies `200` with an empty body and no `Content-Type`
at all, and a service call replies with a *top-level JSON array*. In both cases the action
has already happened — your door opens — and the app is told `-400`
(`INVALID_HTTP_BODY_IN_NETWORK_RESPONSE`). The simulator is more forgiving and shows
success for all three, which makes this easy to miss until you ride. `/api/events`
replies `{"message": "Event garmin_edge fired."}`, which gets through fine.

A `-400`, then, means the request **succeeded** and only the reply was unreadable.

Because the label travels as the event's `action`, one event type can drive every button:
each automation matches on its own label. Renaming a button means updating its
automation too.

Events need a long-lived access token, which can do anything in your Home Assistant. Make
one just for the Edge so you can revoke it alone, and remember the `.prg` holds it in
readable form. If your Home Assistant is reachable only over VPN, a leaked token is far
less exposed than one on an internet-facing instance.

Also in `Config.mc`: `SUCCESS_TONE` / `FAILURE_TONE`, and `TEST_ACTION`, a **Test ping**
button that appears only while the *Show test button* setting is on. Home Assistant
answers `200` to an event whether or not any automation listens, so a green SENT from
Test ping proves the URL, token and phone link before any automation exists. With it off
and one action left, the menu disappears entirely.

### Settings, for a build published to the store

Users configure the store build in **Garmin Connect > the app > Settings**; any setting
left blank falls back to `Config.mc`, so one codebase serves both builds.

HA Control's settings: server URL, access token, event type, glance entity, *Show test
button*, and three button slots of label plus optional entity. A slot with a blank label
is hidden. HA Arrival has its own: server URL, token, event type, enabled, action name
and radius.

**Settings only appear for apps installed from the store**, never for a sideloaded `.prg` —
which is why the compiled-in defaults exist. App properties also survive reinstalls, so on
a sideloaded build a changed default would never reach a device that already has the app;
`Config.mc` is the source of truth there.

## 2. Home Assistant side

One automation per button, each triggered by the event and matching its label:

```yaml
alias: Garage door from Garmin Edge
triggers:
  - trigger: event
    event_type: garmin_edge
    event_data:
      action: Garage
actions:
  - action: cover.toggle
    target:
      entity_id: cover.garage_door
mode: single
```

`homeassistant/garmin_ha_control.yaml` has a complete set, including the Test ping
target (a counter, a toggle and a notification, so it proves delivery without moving
anything).

If Home Assistant sits behind a reverse proxy, it must be told so, or every proxied
request comes back **400 Bad Request** — Home Assistant rejects an `X-Forwarded-For`
header from a proxy it does not trust, while the same request answers `200` when sent
directly.

**On Home Assistant 2026.8 and later, set this in Settings > System > Network, not in
YAML.** HTTP settings now live in a config store that overrides `configuration.yaml`, and
the `http:` YAML block is deprecated (and ignored entirely from 2027.02). The store works
by trial: a change is staged as *pending*, Home Assistant restarts to try it, and **you
must confirm it afterwards or it reverts** — and a trial that was never confirmed is never
retried. So "I edited the YAML, restarted, and nothing changed" is exactly what this
looks like.

Trust the address Home Assistant *observes*, which is not necessarily the one you connect
to. A proxy often listens on one address and egresses from another, and Home Assistant
names the right one in its log:

```
ERROR [homeassistant.components.http.forwarded]
Received X-Forwarded-For header from an untrusted proxy 172.18.0.5
```

That wording also tells you forwarded headers are already enabled — the other failure
("not set-up for reverse proxies") means they are not.

Home Assistant must answer over **HTTPS with a certificate that validates**. Connect IQ
rejects plain HTTP and self-signed certificates.

### Where the certificate is actually checked

The Edge never does TLS for this. `makeWebRequest` is proxied by the Garmin Connect app
on your phone, which opens the real connection and validates the certificate against
**the phone's OS trust store**. There is no Garmin-specific CA chain, and no trust store
on the watch. That has two consequences:

- **A private CA works on iOS**, if you install the root as a profile *and* switch it on
  under Settings > General > About > Certificate Trust Settings. Installing the profile
  alone is not enough.
- **A private CA does not work on Android.** User-installed CAs go in the user trust
  store, which apps ignore unless they opt in through a network security config, and
  Garmin Connect does not. Chrome *does* trust user CAs, so a working browser test on
  Android tells you nothing about whether Garmin Connect will accept it.

### Keeping Home Assistant local but publicly trusted

You do not have to expose Home Assistant to get a trusted certificate. Issue one through
a **DNS-01 challenge**, which proves domain ownership over DNS instead of an inbound
connection:

1. Get a name — your own domain, or a free one from DuckDNS.
2. Issue a Let's Encrypt certificate for it over DNS-01 (the pfSense ACME package, the
   DuckDNS add-on, or certbot with your DNS provider's plugin). No ports are opened.

   If your registrar's API is awkward — Namecheap, for instance, only grants API access
   to accounts with 20+ domains, $50 on balance, or $50 spent in two years, wants a
   whitelisted source IP, and rewrites every record in the zone on each run — you do not
   have to fight it. Either delegate just the challenge with a one-time CNAME from
   `_acme-challenge.<host>` to an acme-dns provider, so the ACME client never touches
   your registrar, or host the zone's DNS at a provider with a sane API (Cloudflare is
   free and keeps your registration where it is), or sidestep the domain entirely with a
   DuckDNS hostname used only for this.
3. Point that name's A record at Home Assistant's **LAN address**. A public record
   holding a private IP is fine and leaks nothing useful.
4. Serve it from your reverse proxy, and make sure you point at `fullchain.pem` — a
   leaf-only certificate fails the handshake even though browsers paper over it.

Any phone then validates it against the public chain with nothing installed. Reaching
the LAN address is up to your VPN, so the button works whenever the VPN is up — if you
would rather not depend on that, a Cloudflare Tunnel gives you a hostname and
certificate with no open ports and no VPN.

Test before touching the Edge:

```bash
curl -i -X POST -H "Content-Type: application/json" -d '{"action":"open"}' \
  https://YOUR-HA-HOST/api/webhook/YOUR-WEBHOOK-ID
```

A 200 with an empty body means it fired. That empty body is what Home Assistant always
returns, and the app treats it as success.

## 3. Build and install

```bash
./build.sh && ./install.sh app           # HA Control, the glance and buttons
./build.sh field && ./install.sh field   # HA Arrival, the data field
./test.sh                                # HA Arrival's unit tests
```

Then eject and restart the Edge. `./simulate.sh` runs HA Control in the Connect IQ
simulator instead — note the simulator makes real web requests, so a successful send
there really does move whatever the action controls.

`developer_key.der` (generated, gitignored) signs the builds. Keep it — a different key
makes the device treat the app as a new install. `./sdk-manager.sh` reopens Garmin's SDK
Manager if you need another device target or a newer SDK.

## Publishing to the Connect IQ store

```bash
./build.sh release          # bin/HaControl.iq  — every product in the manifest, no personal data
./build.sh field-release    # bin/HaArrival.iq  — the data field, likewise
```

They are two separate store listings, since Connect IQ apps are one type each.

**Publishing your own fork?** Give each manifest a new application ID first — the IDs in
this repository belong to the existing store listings, and the store rejects a duplicate:

```bash
python3 -c "import uuid; print(uuid.uuid4().hex)"   # once per manifest
```

The release build compiles against `config/release/Config.mc`, which is blank, instead of
`config/personal/Config.mc`, which holds your server, token and entity IDs and is
gitignored. **Check before every upload**, because a token compiled into a `.prg` is
readable by anyone who downloads it:

```bash
grep -ac "your-domain\|your-token-prefix" bin/HaControl.iq bin/HaArrival.iq   # expect 0 each
```

Then:

1. Sign in at [apps.garmin.com](https://apps.garmin.com) with your Garmin account — the
   same one the SDK Manager uses — and accept the Connect IQ Developer Agreement.
2. Submit an App, upload `bin/HaControl.iq`, and let it validate. The form derives the
   supported devices from the manifest.
3. Fill in the listing. [store/listing.md](store/listing.md) has paste-ready name,
   description, setup instructions and privacy text.
4. Add screenshots. The form states the sizes it wants; the simulator can produce them at
   native device resolution via File > Save Screenshot.
5. Submit. Reviews normally complete within 72 hours, and a rejection comes with reasons
   and can be resubmitted.

While review is pending the app is hidden from the store but installable by you, which is
the easiest way to test the settings UI — settings only appear for store-installed apps,
never for a sideloaded `.prg`.

Two things the reviewers care about that apply here: the app transmits user data (a token,
to a server the user names), so the description should say so plainly, and GDPR obligations
rest with you as the developer. The listing text covers both.

### Building for a different Garmin device

Both manifests already list the Connect IQ 4 Edge models, and all of them compile:
`edge1040`, `edge1050`, `edge840`, `edge540`, `edge550`, `edge850`, `edgeexplore2` and
`edgemtb`. Build for one with `DEVICE=edge840 ./build.sh`.

Screens range from 240x320 to 480x800 and the views size themselves from the drawing
context, so the layout travels. For a watch, download the device in the SDK Manager, add
it under `<iq:products>` in both manifests, and check the button on a round screen —
nothing else is device-specific.

## Error messages

HA Control, on the button screen:

| On screen | Means |
| --- | --- |
| `Action not configured` | The entry has no `:event`/`:service`/`:webhook`/`:url`, or the server URL is empty |
| `Phone not connected` | Bluetooth link to Garmin Connect is down |
| `Timed out` | Phone has no working data connection, or HA is unreachable |
| `HTTPS required` | URL is http://, or the certificate does not validate |
| `Check token` | 401/403 — token missing, wrong, or expired |
| `Not found on server` | 404 — webhook ID or service name does not match |
| `No reply in 20s` | Nothing came back — the relay dropped the reply, or the phone lost its connection |
| `Error -400` | The request **worked**; the reply was unparseable. `:webhook` and `:service` against Home Assistant do this every time — use `:event` |
| `Error 500` etc. | Home Assistant answered with that status |

HA Arrival, in the field while home is unknown:

| In the field | Means |
| --- | --- |
| `Finding` | Asking Home Assistant for `zone.home` |
| `No phone` | Garmin Connect link is down; retries every 30 s |
| `HA timeout` | Phone connected, Home Assistant unreachable — often the VPN; retries every 30 s |
| `Bad token` | 401/403 |
| `No zone.home` | Home Assistant has no home zone |
| `No GPS` | Home is known but there is no fix — or the Positioning permission is missing |
| `Home -400` etc. | Any other code, raw |

## Linux notes

On most systems the SDK Manager and simulator run as Garmin ships them. **Ubuntu 24.04 is
the exception**: both need webkit2gtk-4.0, which 24.04 dropped in favour of 4.1 — and 4.1
is built on libsoup3, so loading it into these libsoup2 tools aborts the process.

What made them work here, without changing any system package:

1. Debian bookworm's `libwebkit2gtk-4.0-37` and `libjavascriptcoregtk-4.0-18`, plus the
   dependencies 24.04 lacks (`libicu72`, `libjpeg62-turbo`, `libavif15`, `libwoff1`,
   `libdav1d6`), unpacked with `dpkg-deb -x` into
   `~/.Garmin/ConnectIQ/compat-libs/root` and put on `LD_LIBRARY_PATH`.
2. WebKit's helper processes are found through a path compiled into the library, and
   `WEBKIT_EXEC_PATH` does not override it in release builds. So the unpacked copy of
   `libwebkit2gtk-4.0.so.37` was patched in place, replacing
   `/usr/lib/x86_64-linux-gnu/webkit2gtk-4.0` with a directory of **exactly the same
   length** under the home directory that holds the helpers. Same length matters: it
   keeps every offset in the library valid.

`sdk-manager.sh`, `simulate.sh` and `test.sh` use those libraries when
`~/.Garmin/ConnectIQ/compat-libs` exists and otherwise run the tools unmodified. The patch
depends on your home directory's path length, which is why it is described rather than
scripted.

## License

GPL-3.0 — see [LICENSE](LICENSE). You may use, modify and redistribute this, provided any
version you distribute is released under the same licence with its source.
