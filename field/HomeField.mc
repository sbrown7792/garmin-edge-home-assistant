import Toybox.Activity;
import Toybox.Application;
import Toybox.Communications;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! Shows the distance home, and fires the arrival event when the ride timer is stopped
//! inside the home zone. Only onTimerStop acts: START would reopen a door you just
//! closed on the way out, auto-pause (onTimerPause) fires at every traffic light, and
//! LAP (onTimerLap) is left alone. The other timer callbacks are logged but ignored, so
//! the ride log shows which callback each physical button really produced.
class HomeField extends WatchUi.SimpleDataField {

    private const STATUS_MS = 15000;
    // How often to ask again while home is still unknown — the phone or VPN may not be
    // connected when the field first loads.
    private const RETRY_MS = 30000;

    // Our own reasons a 200 was unusable. Kept clear of Connect IQ's negative codes,
    // which run from -1 (BLE_ERROR) down past -400.
    private const BAD_BODY = -9001;
    private const NO_ATTRIBUTES = -9002;
    private const NO_COORDINATES = -9003;

    // Event codes in the ride log. 1-6 are ArrivalRules reasons for an ignored STOP.
    private const EV_STOP_FIRED = 7;
    private const EV_SENT_OK = 8;
    private const EV_SENT_FAILED = 9;
    private const EV_HOME_OK = 10;
    private const EV_HOME_FAILED = 11;
    private const EV_START = 12;
    private const EV_PAUSE = 13;
    private const EV_RESUME = 14;
    private const EV_LAP = 15;
    private const EV_LOADED = 16;

    // Bits of the per-second ha_flags field.
    private const FLAG_GPS = 1;
    private const FLAG_HOME = 2;
    private const FLAG_INSIDE = 4;
    private const FLAG_ENABLED = 8;

    // Garmin allots each app very little FIT space: a 48-byte string field fails to
    // allocate, and writing a string longer than its field is a fatal error. So the FIT
    // file holds only the latest event line; the full narrative goes to println.
    private const FIT_TEXT_BYTES = 32;

    private var _homeLat as Double?;
    private var _homeLon as Double?;
    private var _zoneRadius as Number = 0;
    private var _distance as Float?;
    private var _gpsQuality as Number = 0;
    private var _status as String?;
    private var _statusUntil as Number = 0;
    private var _lastFired as Number = -ArrivalRules.REFIRE_MS;
    private var _loadedAt as Number;
    private var _fetching as Boolean = false;
    private var _lastAttempt as Number = 0;
    private var _homeError as Number?;

    private var _fitDistance as FitContributor.Field?;
    private var _fitFlags as FitContributor.Field?;
    private var _fitGps as FitContributor.Field?;
    private var _fitEvents as FitContributor.Field?;
    private var _fitEvent as FitContributor.Field?;
    private var _fitCode as FitContributor.Field?;
    private var _fitLog as FitContributor.Field?;
    private var _eventCount as Number = 0;

    function initialize() {
        SimpleDataField.initialize();
        label = "Home";
        _loadedAt = System.getTimer();
        createLogFields();
        loadCachedHome();
        logEvent(EV_LOADED, "load home=" + (_homeLat != null ? "cached" : "none"));
        fetchHome();
    }

    function compute(info as Activity.Info) as Numeric or Time.Duration or String or Null {
        if (_homeLat == null && !_fetching && System.getTimer() - _lastAttempt >= RETRY_MS) {
            fetchHome();
        }

        var location = info.currentLocation;
        var accuracy = info.currentLocationAccuracy;
        _gpsQuality = accuracy != null ? accuracy as Number : 0;
        if (location != null && _homeLat != null && _homeLon != null) {
            var here = location.toDegrees();
            _distance = ArrivalRules.distanceMetres(here[0].toDouble(), here[1].toDouble(),
                                                    _homeLat as Double, _homeLon as Double);
        }

        recordSecond(location != null);
        return display();
    }

    // --- Timer callbacks -------------------------------------------------------------

    function onTimerStop() as Void {
        var now = System.getTimer();
        var reason = ArrivalRules.decide(now, _loadedAt, _lastFired, AppConfig.arriveEnabled(),
                                         _distance, radius());
        if (reason != ArrivalRules.FIRE) {
            logEvent(reason, "stop ignored: " + ArrivalRules.reasonText(reason) + describePosition());
            return;
        }
        logEvent(EV_STOP_FIRED, "stop fired" + describePosition());
        _lastFired = now;
        fire();
    }

    function onTimerStart() as Void {
        logEvent(EV_START, "start");
    }

    function onTimerPause() as Void {
        logEvent(EV_PAUSE, "autopause");
    }

    function onTimerResume() as Void {
        logEvent(EV_RESUME, "resume");
    }

    function onTimerLap() as Void {
        logEvent(EV_LAP, "lap");
    }

    // --- What the field shows --------------------------------------------------------

    private function radius() as Number {
        var configured = AppConfig.arriveRadius();
        return configured > 0 ? configured : _zoneRadius;
    }

    private function isHome() as Boolean {
        return _distance != null && radius() > 0 && (_distance as Float) <= radius();
    }

    private function display() as String {
        if (_status != null && System.getTimer() < _statusUntil) {
            return _status as String;
        }
        if (!AppConfig.arriveEnabled()) {
            return "Off";
        }
        if (_homeLat == null) {
            if (_fetching) {
                return "Finding";
            }
            return _homeError != null ? homeErrorText(_homeError as Number) : "No home";
        }
        if (_distance == null) {
            return "No GPS";
        }
        if (isHome()) {
            return "STOP opens";
        }
        return formatDistance(_distance as Float);
    }

    private function homeErrorText(code as Number) as String {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return "No phone";
        }
        if (code == Communications.BLE_HOST_TIMEOUT || code == Communications.BLE_SERVER_TIMEOUT ||
            code == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "HA timeout";
        }
        if (code == 401 || code == 403) {
            return "Bad token";
        }
        if (code == 404 || code == NO_COORDINATES) {
            return "No zone.home";
        }
        if (code == BAD_BODY || code == NO_ATTRIBUTES) {
            return "Bad reply";
        }
        return "Home " + code.toString();
    }

    private function showStatus(message as String) as Void {
        _status = message;
        _statusUntil = System.getTimer() + STATUS_MS;
    }

    private function formatDistance(metres as Float) as String {
        if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
            var miles = metres / 1609.344;
            return miles < 0.2
                ? (metres * 3.28084).format("%d") + " ft"
                : miles.format("%.1f") + " mi";
        }
        return metres < 1000
            ? metres.format("%d") + " m"
            : (metres / 1000).format("%.1f") + " km";
    }

    // --- The door --------------------------------------------------------------------

    private function fire() as Void {
        var base = AppConfig.baseUrl();
        var token = AppConfig.token();
        if (base.length() == 0 || token.length() == 0) {
            showStatus("Not set up");
            logEvent(EV_SENT_FAILED, "not set up");
            return;
        }

        var body = {} as Dictionary<Object, Object>;
        body["action"] = AppConfig.arriveAction();
        body["trigger"] = "stop";
        body["distance_m"] = (_distance as Float).toNumber();

        var headers = {} as Dictionary<Object, Object>;
        headers["Content-Type"] = Communications.REQUEST_CONTENT_TYPE_JSON;
        headers["Authorization"] = "Bearer " + token;

        showStatus("Opening");
        Communications.makeWebRequest(base + "/api/events/" + AppConfig.eventType(), body, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onFired));
    }

    function onFired(responseCode as Number, data as Dictionary or String or Null) as Void {
        var ok = responseCode >= 200 && responseCode < 300;
        setCode(responseCode);
        logEvent(ok ? EV_SENT_OK : EV_SENT_FAILED, "sent " + responseCode.toString());
        showStatus(ok ? "Garage sent" : "Failed " + responseCode.toString());
        if (WatchUi.DataField has :showAlert) {
            showAlert(new ArrivalAlert(ok ? "Opening garage" : "Garage failed", ok));
        }
    }

    // --- Where home is ---------------------------------------------------------------

    private function loadCachedHome() as Void {
        var cached = Application.Storage.getValue("home");
        if (cached instanceof Array && (cached as Array).size() == 3) {
            var home = cached as Array;
            _homeLat = (home[0] as Numeric).toDouble();
            _homeLon = (home[1] as Numeric).toDouble();
            _zoneRadius = (home[2] as Numeric).toNumber();
        }
    }

    //! Reads Home Assistant's own zone.home, so nobody has to type coordinates into a
    //! phone. The answer is a JSON object, which the phone relay handles fine.
    private function fetchHome() as Void {
        var base = AppConfig.baseUrl();
        var token = AppConfig.token();
        if (_fetching || base.length() == 0 || token.length() == 0) {
            return;
        }
        _fetching = true;
        _lastAttempt = System.getTimer();

        var headers = {} as Dictionary<Object, Object>;
        headers["Authorization"] = "Bearer " + token;

        Communications.makeWebRequest(base + "/api/states/zone.home", null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onHome));
    }

    function onHome(responseCode as Number, data as Dictionary or String or Null) as Void {
        _fetching = false;
        setCode(responseCode);
        if (responseCode != 200 || !(data instanceof Dictionary)) {
            homeFailed(responseCode == 200 ? BAD_BODY : responseCode);
            return;
        }
        var attributes = (data as Dictionary)["attributes"];
        if (!(attributes instanceof Dictionary)) {
            homeFailed(NO_ATTRIBUTES);
            return;
        }
        var lat = attributes["latitude"];
        var lon = attributes["longitude"];
        var rad = attributes["radius"];
        if (!isNumber(lat) || !isNumber(lon)) {
            homeFailed(NO_COORDINATES);
            return;
        }
        _homeError = null;
        _homeLat = (lat as Numeric).toDouble();
        _homeLon = (lon as Numeric).toDouble();
        _zoneRadius = isNumber(rad) ? (rad as Numeric).toNumber() : 100;
        Application.Storage.setValue("home", [_homeLat, _homeLon, _zoneRadius]);
        logEvent(EV_HOME_OK, "home ok r=" + _zoneRadius.toString());
    }

    private function homeFailed(code as Number) as Void {
        _homeError = code;
        logEvent(EV_HOME_FAILED, "home failed " + code.toString());
    }

    private function isNumber(value as Object?) as Boolean {
        return value instanceof Number || value instanceof Float ||
               value instanceof Double || value instanceof Long;
    }

    // --- Ride log --------------------------------------------------------------------
    //
    // Three places, so a failure on the road can be diagnosed afterwards:
    //  * per-second FIT record fields (also graphable in Garmin Connect)
    //  * the latest event line in the session summary of the FIT file
    //  * System.println, the full narrative, which lands in
    //    Garmin/Apps/LOGS/HaArrival.txt when that file exists on the device

    private function createLogFields() as Void {
        var record = { :mesgType => FitContributor.MESG_TYPE_RECORD };
        _fitDistance = createField("ha_home_m", 0, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m" });
        _fitFlags = createField("ha_flags", 1, FitContributor.DATA_TYPE_UINT8, record);
        _fitGps = createField("ha_gps_q", 2, FitContributor.DATA_TYPE_UINT8, record);
        _fitEvents = createField("ha_events", 3, FitContributor.DATA_TYPE_UINT16, record);
        _fitEvent = createField("ha_event", 4, FitContributor.DATA_TYPE_UINT8, record);
        _fitCode = createField("ha_code", 5, FitContributor.DATA_TYPE_SINT32, record);
        _fitLog = createField("ha_last", 6, FitContributor.DATA_TYPE_STRING,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :count => FIT_TEXT_BYTES });
    }

    private function recordSecond(hasFix as Boolean) as Void {
        var flags = 0;
        if (hasFix) {
            flags |= FLAG_GPS;
        }
        if (_homeLat != null) {
            flags |= FLAG_HOME;
        }
        if (isHome()) {
            flags |= FLAG_INSIDE;
        }
        if (AppConfig.arriveEnabled()) {
            flags |= FLAG_ENABLED;
        }
        if (_fitDistance != null) {
            (_fitDistance as FitContributor.Field).setData(
                _distance != null ? _distance as Float : -1.0f);
        }
        if (_fitFlags != null) {
            (_fitFlags as FitContributor.Field).setData(flags);
        }
        if (_fitGps != null) {
            (_fitGps as FitContributor.Field).setData(_gpsQuality);
        }
    }

    private function setCode(code as Number) as Void {
        if (_fitCode != null) {
            (_fitCode as FitContributor.Field).setData(code);
        }
    }

    private function describePosition() as String {
        var d = _distance != null ? (_distance as Float).toNumber().toString() : "-";
        return " d=" + d + " r=" + radius().toString() + " q=" + _gpsQuality.toString();
    }

    private function logEvent(code as Number, text as String) as Void {
        _eventCount += 1;
        var now = System.getClockTime();
        var line = Lang.format("$1$:$2$:$3$ $4$",
            [now.hour.format("%02d"), now.min.format("%02d"), now.sec.format("%02d"), text]);
        System.println(line);

        if (_fitEvents != null) {
            (_fitEvents as FitContributor.Field).setData(_eventCount);
        }
        if (_fitEvent != null) {
            (_fitEvent as FitContributor.Field).setData(code);
        }
        if (_fitLog != null) {
            // The count includes the terminator; one byte over crashes the app.
            var limit = FIT_TEXT_BYTES - 1;
            var fitted = line.length() > limit ? line.substring(0, limit) : line;
            (_fitLog as FitContributor.Field).setData(fitted);
        }
    }
}

//! Full-screen confirmation, since the field may be on a page you are not looking at
//! when you press STOP.
class ArrivalAlert extends WatchUi.DataFieldAlert {

    private var _message as String;
    private var _ok as Boolean;

    function initialize(message as String, ok as Boolean) {
        DataFieldAlert.initialize();
        _message = message;
        _ok = ok;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, _ok ? Graphics.COLOR_DK_GREEN : Graphics.COLOR_DK_RED);
        dc.clear();
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_MEDIUM, _message,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
