import Toybox.Application;
import Toybox.Lang;

//! Resolves configuration at runtime. App settings entered in Garmin Connect win; where
//! a setting is blank the compiled-in value from Config.mc is used, so a sideloaded
//! build keeps working without any settings UI at all.
(:glance)
module AppConfig {

    function baseUrl() as String {
        return stringProperty("haUrl", HA_BASE_URL);
    }

    function token() as String {
        return stringProperty("haToken", HA_TOKEN);
    }

    function eventType() as String {
        return stringProperty("eventType", EVENT_TYPE);
    }

    function arriveAction() as String {
        return stringProperty("arriveAction", ARRIVE_ACTION);
    }

    //! Metres. Zero or less means "use the radius of Home Assistant's home zone".
    function arriveRadius() as Number {
        try {
            var value = Application.Properties.getValue("arriveRadius");
            if (value instanceof Number) {
                return value as Number;
            }
        } catch (e) {
        }
        return ARRIVE_RADIUS;
    }

    function arriveEnabled() as Boolean {
        try {
            var value = Application.Properties.getValue("arriveEnabled");
            if (value instanceof Boolean) {
                return value as Boolean;
            }
        } catch (e) {
        }
        return true;
    }

    function statusEntity() as String {
        return stringProperty("statusEntity", STATUS_ENTITY);
    }

    function showTestButton() as Boolean {
        try {
            return Application.Properties.getValue("showTest") as Boolean;
        } catch (e) {
            return false;
        }
    }

    //! Button slots from settings, falling back to ACTIONS when none are filled in.
    function actions() as Array<Dictionary<Symbol, String>> {
        var configured = [] as Array<Dictionary<Symbol, String>>;
        for (var i = 1; i <= 3; i++) {
            var label = stringProperty("label" + i, "");
            if (label.length() > 0) {
                configured.add({
                    :label => label,
                    :event => eventType(),
                    :entity => stringProperty("entity" + i, "")
                });
            }
        }
        var list = configured.size() > 0 ? configured : ACTIONS;
        if (showTestButton()) {
            list = (list as Array<Dictionary<Symbol, String>>).addAll([TEST_ACTION]);
        }
        return list;
    }

    function stringProperty(key as String, fallback as String) as String {
        var value = null;
        try {
            value = Application.Properties.getValue(key);
        } catch (e) {
            value = null;
        }
        if (value instanceof String && (value as String).length() > 0) {
            return value as String;
        }
        return fallback;
    }
}
