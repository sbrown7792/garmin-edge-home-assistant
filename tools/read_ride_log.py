#!/usr/bin/env python3
"""Print what the HA Arrival data field recorded during a ride.

    pip install fitdecode
    python3 tools/read_ride_log.py path/to/activity.fit

The field writes these developer fields into the activity:

    record  ha_home_m   metres to home, -1 when unknown
            ha_flags    1 GPS fix, 2 home known, 4 inside radius, 8 enabled
            ha_gps_q    GPS quality, 0 (none) to 4 (good)
            ha_events   running count of logged events
            ha_event    code of the latest event (see EVENTS)
            ha_code     latest HTTP / Connect IQ response code
    session ha_last     text of the latest event

The printout shows every second on which the event count changed, which is where the
story is, plus a summary of GPS coverage and distance.
"""

import sys

import fitdecode

EVENTS = {
    1: "STOP ignored: settling",
    2: "STOP ignored: too soon",
    3: "STOP ignored: disabled",
    4: "STOP ignored: no GPS",
    5: "STOP ignored: no home",
    6: "STOP ignored: outside radius",
    7: "STOP fired",
    8: "sent OK",
    9: "send failed",
    10: "home fetched",
    11: "home fetch failed",
    12: "START",
    13: "auto-pause",
    14: "resume",
    15: "LAP",
    16: "field loaded",
}

FLAGS = [(1, "gps"), (2, "home"), (4, "inside"), (8, "on")]


def developer_values(frame):
    values = {}
    for field in frame.fields:
        if getattr(field, "is_developer_data", False) and field.name:
            values[field.name] = field.value
    return values


def describe_flags(flags):
    if flags is None:
        return "-"
    return ",".join(name for bit, name in FLAGS if flags & bit) or "none"


def main(path):
    rows = []
    last_text = None

    with fitdecode.FitReader(path) as fit:
        for frame in fit:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name == "record":
                values = developer_values(frame)
                if values:
                    stamp = frame.get_value("timestamp", fallback=None)
                    rows.append((stamp, values))
            elif frame.name == "session":
                values = developer_values(frame)
                last_text = values.get("ha_last", last_text)

    if not rows:
        print("No HA Arrival data in this file — was the field on a data screen?")
        return 1

    print(f"{len(rows)} records with HA Arrival data\n")
    print("Events:")
    previous = None
    for stamp, values in rows:
        count = values.get("ha_events")
        if count is not None and count != previous:
            code = values.get("ha_event")
            print(f"  {stamp:%H:%M:%S}  #{count:<3} {EVENTS.get(code, f'code {code}'):<30}"
                  f"  dist={values.get('ha_home_m', -1):>8.0f} m"
                  f"  flags={describe_flags(values.get('ha_flags'))}"
                  f"  gps_q={values.get('ha_gps_q')}"
                  f"  code={values.get('ha_code')}")
            previous = count

    with_fix = sum(1 for _, v in rows if (v.get("ha_flags") or 0) & 1)
    known = [v["ha_home_m"] for _, v in rows if v.get("ha_home_m", -1) >= 0]
    inside = sum(1 for _, v in rows if (v.get("ha_flags") or 0) & 4)
    print("\nSummary:")
    print(f"  GPS fix on {with_fix} of {len(rows)} records "
          f"({100 * with_fix / len(rows):.0f}%)")
    if known:
        print(f"  distance home ranged {min(known):.0f} m to {max(known):.0f} m")
    else:
        print("  distance home was never known")
    print(f"  inside the radius on {inside} records")
    print(f"  last event text: {last_text!r}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
