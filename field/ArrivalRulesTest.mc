import Toybox.Lang;
import Toybox.Test;

// Unit tests, compiled only with --unit-test. Run with ./test.sh.

(:test)
function firesWhenStoppedInsideTheRadius(logger as Logger) as Boolean {
    return ArrivalRules.shouldFire(100000, 0, -60000, true, 40.0f, 100);
}

(:test)
function firesAtExactlyTheRadius(logger as Logger) as Boolean {
    return ArrivalRules.shouldFire(100000, 0, -60000, true, 100.0f, 100);
}

(:test)
function ignoresStopOutsideTheRadius(logger as Logger) as Boolean {
    return !ArrivalRules.shouldFire(100000, 0, -60000, true, 100.5f, 100);
}

(:test)
function ignoresStopJustAfterTheFieldLoads(logger as Logger) as Boolean {
    // Reopening an activity must never open the door on its own.
    return !ArrivalRules.shouldFire(2999, 0, -60000, true, 10.0f, 100);
}

(:test)
function firesOnceTheSettleWindowHasPassed(logger as Logger) as Boolean {
    return ArrivalRules.shouldFire(3000, 0, -60000, true, 10.0f, 100);
}

(:test)
function ignoresASecondStopWithinAMinute(logger as Logger) as Boolean {
    return !ArrivalRules.shouldFire(159999, 0, 100000, true, 10.0f, 100);
}

(:test)
function firesAgainAfterAMinute(logger as Logger) as Boolean {
    return ArrivalRules.shouldFire(160000, 0, 100000, true, 10.0f, 100);
}

(:test)
function ignoresStopWhenDisabled(logger as Logger) as Boolean {
    return !ArrivalRules.shouldFire(100000, 0, -60000, false, 10.0f, 100);
}

(:test)
function ignoresStopWithoutAGpsFix(logger as Logger) as Boolean {
    return !ArrivalRules.shouldFire(100000, 0, -60000, true, null, 100);
}

(:test)
function ignoresStopBeforeHomeIsKnown(logger as Logger) as Boolean {
    // A radius of zero means zone.home has not been fetched yet.
    return !ArrivalRules.shouldFire(100000, 0, -60000, true, 0.0f, 0);
}

(:test)
function measuresAShortEastWestHop(logger as Logger) as Boolean {
    // 0.001 degrees of longitude at the equator is 111.19 m.
    var d = ArrivalRules.distanceMetres(0.0d, 0.0d, 0.0d, 0.001d);
    logger.debug("0.001 deg lon at equator = " + d);
    return d > 111.0 && d < 111.4;
}

(:test)
function measuresADriveway(logger as Logger) as Boolean {
    // Two points 50 m apart along a meridian: 50 / 111195 degrees of latitude.
    var d = ArrivalRules.distanceMetres(45.0d, -70.0d, 45.0d + 50.0d / 111195.0d, -70.0d);
    logger.debug("50 m meridian hop = " + d);
    return d > 49.5 && d < 50.5;
}

(:test)
function measuresZeroForTheSamePoint(logger as Logger) as Boolean {
    return ArrivalRules.distanceMetres(42.3d, -71.1d, 42.3d, -71.1d) < 0.01;
}

// The reason codes feed the ride log, so a wrong one would send the diagnosis astray.

(:test)
function explainsASettlingPress(logger as Logger) as Boolean {
    return ArrivalRules.decide(100, 0, -60000, true, 10.0f, 100) == ArrivalRules.SETTLING;
}

(:test)
function explainsARepeatPress(logger as Logger) as Boolean {
    return ArrivalRules.decide(100000, 0, 90000, true, 10.0f, 100) == ArrivalRules.TOO_SOON;
}

(:test)
function explainsADisabledField(logger as Logger) as Boolean {
    return ArrivalRules.decide(100000, 0, -60000, false, 10.0f, 100) == ArrivalRules.DISABLED;
}

(:test)
function explainsAMissingHome(logger as Logger) as Boolean {
    // Missing home is reported ahead of missing GPS: it is the one that needs fixing.
    return ArrivalRules.decide(100000, 0, -60000, true, null, 0) == ArrivalRules.NO_HOME;
}

(:test)
function explainsAMissingFix(logger as Logger) as Boolean {
    return ArrivalRules.decide(100000, 0, -60000, true, null, 100) == ArrivalRules.NO_GPS;
}

(:test)
function explainsAStopTooFarAway(logger as Logger) as Boolean {
    return ArrivalRules.decide(100000, 0, -60000, true, 850.0f, 100) == ArrivalRules.OUTSIDE;
}

(:test)
function explainsAFiringStop(logger as Logger) as Boolean {
    return ArrivalRules.decide(100000, 0, -60000, true, 20.0f, 100) == ArrivalRules.FIRE;
}
