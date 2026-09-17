import Toybox.Lang;
import Toybox.Math;

//! The decision to open the door, kept free of device state so it can be unit tested.
module ArrivalRules {

    // Presses this soon after the field loads are ignored, so reopening an activity or
    // switching profiles can never fire the door by itself.
    const SETTLE_MS = 3000;
    // One door command per stop, even if STOP is pressed twice in quick succession.
    const REFIRE_MS = 60000;

    // What decide() concluded. The non-zero values double as log codes for why a STOP
    // was ignored.
    const FIRE = 0;
    const SETTLING = 1;
    const TOO_SOON = 2;
    const DISABLED = 3;
    const NO_GPS = 4;
    const NO_HOME = 5;
    const OUTSIDE = 6;

    function decide(now as Number, loadedAt as Number, lastFired as Number,
                    enabled as Boolean, distance as Float?, radius as Number) as Number {
        if (now - loadedAt < SETTLE_MS) {
            return SETTLING;
        }
        if (now - lastFired < REFIRE_MS) {
            return TOO_SOON;
        }
        if (!enabled) {
            return DISABLED;
        }
        if (radius <= 0) {
            return NO_HOME;
        }
        if (distance == null) {
            return NO_GPS;
        }
        return (distance as Float) <= radius ? FIRE : OUTSIDE;
    }

    function shouldFire(now as Number, loadedAt as Number, lastFired as Number,
                        enabled as Boolean, distance as Float?, radius as Number) as Boolean {
        return decide(now, loadedAt, lastFired, enabled, distance, radius) == FIRE;
    }

    function reasonText(reason as Number) as String {
        switch (reason) {
            case FIRE: return "fire";
            case SETTLING: return "settling";
            case TOO_SOON: return "too soon";
            case DISABLED: return "disabled";
            case NO_GPS: return "no gps";
            case NO_HOME: return "no home";
            case OUTSIDE: return "outside";
        }
        return "?";
    }

    //! Great-circle distance in metres. Accurate to well under a metre over the few
    //! kilometres that matter here.
    function distanceMetres(lat1 as Double, lon1 as Double,
                            lat2 as Double, lon2 as Double) as Float {
        var rad = Math.PI / 180.0;
        var dLat = (lat2 - lat1) * rad;
        var dLon = (lon2 - lon1) * rad;
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(lat1 * rad) * Math.cos(lat2 * rad) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2);
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return (6371000.0 * c).toFloat();
    }
}
