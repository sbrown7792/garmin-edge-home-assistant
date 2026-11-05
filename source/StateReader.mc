import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Reads one entity's state from Home Assistant and knows how to draw it. Shared by the
//! glance and the button screen, so both render the same door in the same colours.
(:glance)
class StateReader {

    // While the door moves, read again this often, at most this many times: 45 s, for
    // a door that takes about 15 s plus however long Home Assistant takes to notice.
    private const FOLLOW_MS = 3000;
    private const FOLLOW_READS = 15;
    // After an Edge restart the phone relay can sit on requests for a minute or more
    // and then fail them all at once (seen: 53 s and 77 s, then -1004). Sending another
    // meanwhile only fills its queue until everything bounces with -101. So one read at
    // a time: past WAIT_MS the screen says so, and only past LOST_MS is the read written
    // off, in case the relay really did drop it and a glance would otherwise wait for
    // hours.
    private const WAIT_MS = 20000;
    private const LOST_MS = 120000;

    private var _entity as String;
    private var _state as String?;
    private var _name as String?;
    private var _busy as Boolean = false;
    private var _busySince as Number = 0;
    private var _problem as String?;
    // Set by an answer that reading again cannot fix (404, bad token): ends a follow.
    private var _stopped as Boolean = false;

    private var _timer as Timer.Timer?;
    private var _readsLeft as Number = 0;
    private var _from as String?;
    private var _seenMoving as Boolean = false;

    // "glance" or "screen", so the log says which of the two made each request.
    private var _tag as String;
    private var _reads as Number = 0;

    function initialize(entity as String, tag as String) {
        _entity = entity;
        _tag = tag;
        var cached = Application.Storage.getValue("state:" + entity);
        if (cached instanceof String) {
            _state = cached as String;
        }
        var cachedName = Application.Storage.getValue("name:" + entity);
        if (cachedName instanceof String) {
            _name = cachedName as String;
        }
    }

    function getState() as String? {
        return _state;
    }

    function getName() as String? {
        return _name;
    }

    function hasEntity() as Boolean {
        return _entity.length() > 0;
    }

    //! True when the next toggle would close rather than open.
    function isOpen() as Boolean {
        return openness() > 0.5;
    }

    //! Reads now and keeps reading until the door is at rest; see DoorMotion. After a
    //! press, pass the state the press started from: the first read then waits a tick,
    //! since the event and the read would otherwise go out over the relay together.
    //!
    //! A repeating timer rather than a read per answer, so a reply the relay drops
    //! cannot end the loop early, and the loop ends after FOLLOW_READS ticks whatever
    //! the relay does.
    function follow(from as String?) as Void {
        Log.line(_tag + " follow from=" + (from != null ? from : "-") +
                 " cached=" + (_state != null ? _state : "-"));
        _readsLeft = FOLLOW_READS;
        _from = from;
        _seenMoving = false;
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        var timer = _timer as Timer.Timer;
        timer.stop();
        timer.start(method(:onFollowTick), FOLLOW_MS, true);
        if (from == null) {
            refresh();
        }
    }

    function stop() as Void {
        _readsLeft = 0;
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
        }
    }

    function onFollowTick() as Void {
        _readsLeft -= 1;
        if (_readsLeft <= 0) {
            Log.line(_tag + " follow gave up at " + (_state != null ? _state : "-"));
            stop();
            return;
        }
        refresh();
    }

    //! Called after every answer, good or bad. A failed read leaves the old state, which
    //! still counts as unsettled after a press, so a brief relay hiccup is ridden out.
    private function checkSettled() as Void {
        if (_readsLeft <= 0) {
            return;
        }
        if (DoorMotion.isMoving(_state)) {
            _seenMoving = true;
        }
        if (_stopped || !DoorMotion.keepReading(_state, _from, _seenMoving)) {
            Log.line(_tag + " follow done at " + (_state != null ? _state : "-"));
            stop();
        }
    }

    function refresh() as Void {
        var base = AppConfig.baseUrl();
        var token = AppConfig.token();
        if (_entity.length() == 0 || base.length() == 0 || token.length() == 0) {
            return;
        }
        if (_busy) {
            var waited = System.getTimer() - _busySince;
            if (waited < WAIT_MS) {
                return;
            }
            if (waited < LOST_MS) {
                if (_problem == null || !(_problem as String).equals("Waiting for phone")) {
                    Log.line(_tag + " read #" + _reads + " still waiting after " + waited + " ms");
                    _problem = "Waiting for phone";
                    WatchUi.requestUpdate();
                }
                return;
            }
            Log.line(_tag + " read #" + _reads + " written off after " + waited + " ms");
        }
        _busy = true;
        _busySince = System.getTimer();
        _reads += 1;
        Log.line(_tag + " read #" + _reads + " GET /api/states/" + _entity + " " + Log.links());

        var headers = {} as Dictionary<Object, Object>;
        headers["Authorization"] = "Bearer " + token;

        Communications.makeWebRequest(base + "/api/states/" + _entity, null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onState));
    }

    function onState(responseCode as Number, data as Dictionary or String or Null) as Void {
        var took = System.getTimer() - _busySince;
        _busy = false;
        _stopped = false;
        if (responseCode == 200 && data instanceof Dictionary) {
            Log.line(_tag + " read #" + _reads + " -> 200 in " + took + " ms state=" +
                     Log.brief((data as Dictionary)["state"]));
        } else {
            Log.line(_tag + " read #" + _reads + " -> " + responseCode + " in " + took + " ms " +
                     Log.links() + " body=" + Log.brief(data));
        }
        if (responseCode == 404 || responseCode == 401 || responseCode == 403) {
            // Reading again will not help, and the last state seen is not worth showing.
            // A 404 usually means the entity was renamed in Home Assistant, which
            // re-adding an integration does, and that is invisible from the Edge
            // otherwise.
            _problem = responseCode == 404 ? "Not found in HA" : "Check token";
            _stopped = true;
            _state = null;
            Application.Storage.deleteValue("state:" + _entity);
        } else if (responseCode != 200 || !(data instanceof Dictionary)) {
            // No phone, a timeout and the like. Offline is normal on a bike, so the door
            // keeps its last known position, but the text says why it is not fresh.
            _problem = describe(responseCode);
        } else {
            _problem = null;
            var state = data["state"];
            if (state instanceof String) {
                _state = state as String;
                Application.Storage.setValue("state:" + _entity, _state);
            }
            var attributes = data["attributes"];
            if (attributes instanceof Dictionary) {
                var name = attributes["friendly_name"];
                if (name instanceof String) {
                    _name = name as String;
                    Application.Storage.setValue("name:" + _entity, _name);
                }
            }
        }
        checkSettled();
        WatchUi.requestUpdate();
    }

    //! Worded like HA Arrival's field, and short enough for the glance.
    private function describe(code as Number) as String {
        if (code == 200) {
            return "Bad reply";
        }
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return "No phone";
        }
        if (code == Communications.BLE_HOST_TIMEOUT || code == Communications.BLE_SERVER_TIMEOUT ||
            code == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "HA timeout";
        }
        if (code == Communications.SECURE_CONNECTION_REQUIRED) {
            return "HTTPS required";
        }
        if (code == Communications.REQUEST_CONNECTION_DROPPED) {
            return "Link dropped";
        }
        if (code == Communications.BLE_QUEUE_FULL) {
            return "Queue full";
        }
        return "Error " + code.toString();
    }

    //! Why the last read failed, shown in place of the state; null after a good read.
    function problemText() as String? {
        return _problem;
    }

    //! Colour for whichever of problemText() or stateText() is on screen. A problem is
    //! grey whatever the door's last colour, so "No phone" never reads as a state.
    function textColor() as ColorValue {
        return _problem != null ? Theme.unknownColor() : color();
    }

    function stateText() as String? {
        if (!(_state instanceof String)) {
            return null;
        }
        var value = _state as String;
        if (value.length() == 0) {
            return null;
        }
        return value.substring(0, 1).toUpper() + value.substring(1, value.length());
    }

    function openness() as Float {
        if (!(_state instanceof String)) {
            return 0.35;
        }
        var s = _state as String;
        if (s.equals("closed") || s.equals("off") || s.equals("locked")) {
            return 0.0;
        }
        if (s.equals("opening") || s.equals("closing")) {
            return 0.5;
        }
        return 1.0;
    }

    function color() as ColorValue {
        if (!(_state instanceof String)) {
            return Theme.unknownColor();
        }
        var s = _state as String;
        if (s.equals("closed") || s.equals("off") || s.equals("locked")) {
            return Theme.closedColor();
        }
        if (s.equals("opening") || s.equals("closing")) {
            return Theme.movingColor();
        }
        if (s.equals("unavailable") || s.equals("unknown")) {
            return Theme.unknownColor();
        }
        return Theme.openColor();
    }

    //! A frame with a panel that sits low when closed and high when open, the same shape
    //! Home Assistant draws on its cover card.
    function drawDoor(dc as Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        dc.setColor(Theme.frameColor(), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 3);

        var panelHeight = (h * (1.0 - openness())).toNumber();
        if (panelHeight < 2 && openness() < 1.0) {
            panelHeight = 2;
        }
        if (panelHeight > 0) {
            dc.setColor(color(), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x + 2, y + h - panelHeight, w - 4, panelHeight - 2, 2);
        }
    }
}
