import Toybox.Lang;
import Toybox.Test;

// Unit tests, compiled only with --unit-test. Run with ./test.sh.

(:test)
function keepsReadingWhileTheDoorIsOpening(logger as Logger) as Boolean {
    return DoorMotion.keepReading("opening", null, false);
}

(:test)
function keepsReadingWhileTheDoorIsClosing(logger as Logger) as Boolean {
    return DoorMotion.keepReading("closing", "open", true);
}

(:test)
function stopsOnceAMovingDoorComesToRest(logger as Logger) as Boolean {
    return !DoorMotion.keepReading("open", null, true);
}

(:test)
function stopsAtOnceForAGlanceThatFindsTheDoorStill(logger as Logger) as Boolean {
    return !DoorMotion.keepReading("closed", null, false);
}

(:test)
function waitsForHomeAssistantToRegisterThePress(logger as Logger) as Boolean {
    // Read straight after pressing OPEN, before Home Assistant has caught up.
    return DoorMotion.keepReading("closed", "closed", false);
}

(:test)
function stopsWhenTheDoorJumpsStraightToItsEndState(logger as Logger) as Boolean {
    // Some openers report "open" without ever reporting "opening".
    return !DoorMotion.keepReading("open", "closed", false);
}

(:test)
function stopsWhenTheDoorWentAndCameBack(logger as Logger) as Boolean {
    // Seen opening, now closed again: an obstruction reversal, or a second press.
    return !DoorMotion.keepReading("closed", "closed", true);
}

(:test)
function treatsAnUnknownStateAsNotMoving(logger as Logger) as Boolean {
    return !DoorMotion.isMoving(null) && !DoorMotion.keepReading(null, null, false);
}
