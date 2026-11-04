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
    // The phone relay sometimes never answers. Without a limit, one lost reply would
    // block every later read for the life of the glance, which can be hours.
    private const STUCK_MS = 20000;

    private var _entity as String;
    private var _state as String?;
    private var _name as String?;
    private var _busy as Boolean = false;
    private var _busySince as Number = 0;
    private var _problem as String?;

    private var _timer as Timer.Timer?;
    private var _readsLeft as Number = 0;
    private var _from as String?;
    private var _seenMoving as Boolean = false;

    function initialize(entity as String) {
        _entity = entity;
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
        if (_problem != null || !DoorMotion.keepReading(_state, _from, _seenMoving)) {
            stop();
        }
    }

    function refresh() as Void {
        var base = AppConfig.baseUrl();
        var token = AppConfig.token();
        if (_entity.length() == 0 || base.length() == 0 || token.length() == 0) {
            return;
        }
        if (_busy && System.getTimer() - _busySince < STUCK_MS) {
            return;
        }
        _busy = true;
        _busySince = System.getTimer();

        var headers = {} as Dictionary<Object, Object>;
        headers["Authorization"] = "Bearer " + token;

        Communications.makeWebRequest(base + "/api/states/" + _entity, null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onState));
    }

    function onState(responseCode as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        if (responseCode == 404 || responseCode == 401 || responseCode == 403) {
            // Say so rather than keep showing the last state seen. A 404 usually means
            // the entity was renamed in Home Assistant, which re-adding an integration
            // does, and that is invisible from the Edge otherwise.
            _problem = responseCode == 404 ? "Not found in HA" : "Check token";
            _state = null;
            Application.Storage.deleteValue("state:" + _entity);
        } else if (responseCode == 200 && data instanceof Dictionary) {
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
        // Anything else (no phone, a timeout) keeps the last state seen: offline is normal
        // on a bike, and the last known position is still the best guess.
        checkSettled();
        WatchUi.requestUpdate();
    }

    //! Shown in place of the state when Home Assistant refused to give one.
    function problemText() as String? {
        return _problem;
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
