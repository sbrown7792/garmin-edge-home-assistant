# Store listing copy

Paste-ready text for the Connect IQ submission form. Written for store visitors, not for
you — it assumes no knowledge of this repo.

## Name

HA Control

## Short description

Trigger Home Assistant actions from your Edge — open the garage, toggle a light, run a
script — and see the state without reaching for your phone.

## Full description

HA Control puts your Home Assistant on the bike computer. Add a button, press it, and
Home Assistant does the rest.

**What it does**

- One button per action: open a garage, toggle a light, start a script
- The button knows the state: it reads the entity you point it at and says OPEN or CLOSE
  accordingly, so a single screen works both ways
- A home screen glance shows the current state at a distance — green and closed, orange
  and open, yellow while moving — without opening the app
- Works while an activity is recording

**What you need**

- Home Assistant reachable over HTTPS with a certificate that validates. A self-signed
  certificate will not work; Nabu Casa Cloud, a reverse proxy with a real certificate, or
  a Cloudflare Tunnel all will.
- A long-lived access token from your Home Assistant profile
- Your phone connected to Garmin Connect, which relays the request

**Setting it up**

1. In Garmin Connect, open this app's settings and fill in your server URL and token.
2. Set an event type, or keep the default `garmin_edge`.
3. Name a button, for example "Garage", and optionally give it the entity whose state you
   want shown, for example `cover.garage_door`.
4. In Home Assistant, create an automation triggered by that event:

```yaml
triggers:
  - trigger: event
    event_type: garmin_edge
    event_data:
      action: Garage
actions:
  - action: cover.toggle
    target:
      entity_id: cover.garage_door
```

Turn on "Show test button" while setting up. It confirms your URL, token and phone link
even before any automation exists, because Home Assistant accepts the event either way.

**Privacy**

Your server address and token are stored on your device and in your Garmin Connect app
settings, and are sent only to the Home Assistant server you nominate. The developer
receives nothing; there is no analytics, no third-party service, and no account.

## Support

- Support email: <your email>
- Source and issues: <your repository URL>

## Privacy policy

Needed if the form asks for one. Suggested text:

> HA Control stores the Home Assistant server address and access token that you enter in
> the app's settings. These are held on your Garmin device and in your Garmin Connect app
> settings, and are transmitted only to the server address you provide, in order to
> trigger the actions you configure. No data is collected, transmitted to, or stored by
> the developer or any third party. Removing the app removes the stored settings.
