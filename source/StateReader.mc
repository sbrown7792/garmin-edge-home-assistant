import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! Reads one entity's state from Home Assistant and knows how to draw it. Shared by the
//! glance and the button screen, so both render the same door in the same colours.
(:glance)
class StateReader {

    private var _entity as String;
    private var _state as String?;
    private var _name as String?;
    private var _busy as Boolean = false;

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

    function refresh() as Void {
        var base = AppConfig.baseUrl();
        var token = AppConfig.token();
        if (_busy || _entity.length() == 0 || base.length() == 0 || token.length() == 0) {
            return;
        }
        _busy = true;

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
        if (responseCode == 200 && data instanceof Dictionary) {
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
        WatchUi.requestUpdate();
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
            return Graphics.COLOR_LT_GRAY;
        }
        var s = _state as String;
        if (s.equals("closed") || s.equals("off") || s.equals("locked")) {
            return Graphics.COLOR_GREEN;
        }
        if (s.equals("opening") || s.equals("closing")) {
            return Graphics.COLOR_YELLOW;
        }
        if (s.equals("unavailable") || s.equals("unknown")) {
            return Graphics.COLOR_LT_GRAY;
        }
        return Graphics.COLOR_ORANGE;
    }

    //! A frame with a panel that sits low when closed and high when open, the same shape
    //! Home Assistant draws on its cover card.
    function drawDoor(dc as Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
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
