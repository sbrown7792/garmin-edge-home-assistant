import Toybox.Lang;

//! When to stop re-reading a door. A garage door takes 15 s or so to travel, so a single
//! read just after a press, or just after the glance starts, almost always lands
//! mid-travel. If that is the last read, "Opening" stays on screen indefinitely. Kept
//! free of device state so ./test.sh can cover it.
(:glance)
module DoorMotion {

    function isMoving(state as String?) as Boolean {
        if (state == null) {
            return false;
        }
        var s = state as String;
        return s.equals("opening") || s.equals("closing");
    }

    //! from is the state when the button was pressed, or null when nothing was pressed
    //! and the reader only wants a moving door to come to rest.
    function keepReading(state as String?, from as String?, seenMoving as Boolean) as Boolean {
        if (isMoving(state)) {
            return true;
        }
        // Home Assistant can take a moment to register a press, and some openers report
        // the end state without ever reporting "opening". So the state the press started
        // from is not an answer yet, unless the door has been seen moving, in which case
        // it went and came back.
        if (from != null && state != null && !seenMoving) {
            return (state as String).equals(from as String);
        }
        return false;
    }
}
