import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

(:glance)
class HaGlanceView extends WatchUi.GlanceView {

    private var _reader as StateReader;

    function initialize() {
        GlanceView.initialize();
        _reader = new StateReader(AppConfig.statusEntity());
    }

    function onShow() as Void {
        _reader.refresh();
    }

    function onUpdate(dc as Dc) as Void {
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var textX = 6;
        if (_reader.hasEntity()) {
            var doorWidth = 26;
            var doorHeight = (height * 0.52).toNumber();
            _reader.drawDoor(dc, 6, (height - doorHeight) / 2, doorWidth, doorHeight);
            textX = 6 + doorWidth + 10;
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, height / 3, Graphics.FONT_SMALL, title(),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(_reader.color(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, (height * 2) / 3, Graphics.FONT_XTINY, subtitle(),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function title() as String {
        var name = _reader.getName();
        if (name instanceof String) {
            return name as String;
        }
        var actions = AppConfig.actions();
        if (actions.size() > 0) {
            var label = actions[0][:label];
            if (label instanceof String) {
                return label as String;
            }
        }
        return "Home Assistant";
    }

    private function subtitle() as String {
        var state = _reader.stateText();
        if (state instanceof String) {
            return state as String;
        }
        var last = Application.Storage.getValue("lastAction");
        if (last instanceof String) {
            return last as String;
        }
        return "Tap to open";
    }
}
