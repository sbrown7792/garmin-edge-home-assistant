import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

(:glance)
class HaGlanceView extends WatchUi.GlanceView {

    // The Edge keeps its glances running (liveUpdates in the device profile), so a
    // single read when the glance starts would go stale for as long as it stays up,
    // missing the door being moved from Home Assistant or the wall button.
    private const REREAD_MS = 60000;

    private var _reader as StateReader;
    private var _reread as Timer.Timer?;

    function initialize() {
        GlanceView.initialize();
        _reader = new StateReader(AppConfig.statusEntity(), "glance");
    }

    function onShow() as Void {
        _reader.follow(null);
        if (_reread == null) {
            _reread = new Timer.Timer();
        }
        var reread = _reread as Timer.Timer;
        reread.stop();
        reread.start(method(:onReread), REREAD_MS, true);
    }

    function onHide() as Void {
        if (_reread != null) {
            (_reread as Timer.Timer).stop();
        }
        _reader.stop();
    }

    function onReread() as Void {
        _reader.follow(null);
    }

    function onUpdate(dc as Dc) as Void {
        var height = dc.getHeight();

        dc.setColor(Theme.text(), Theme.background());
        dc.clear();

        var textX = 6;
        if (_reader.hasEntity()) {
            var doorWidth = 26;
            var doorHeight = (height * 0.52).toNumber();
            _reader.drawDoor(dc, 6, (height - doorHeight) / 2, doorWidth, doorHeight);
            textX = 6 + doorWidth + 10;
        }

        dc.setColor(Theme.text(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, height / 3, Graphics.FONT_SMALL, title(),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(_reader.textColor(), Graphics.COLOR_TRANSPARENT);
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
        var problem = _reader.problemText();
        if (problem instanceof String) {
            return problem as String;
        }
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
