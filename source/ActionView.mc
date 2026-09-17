import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class ActionView extends WatchUi.View {

    private var _runner as ActionRunner;
    private var _reader as StateReader;
    private var _refresh as Timer.Timer?;
    private var _refreshesLeft as Number = 0;

    function initialize(runner as ActionRunner) {
        View.initialize();
        _runner = runner;
        _reader = new StateReader(runner.getEntity());
    }

    function onShow() as Void {
        _reader.refresh();
    }

    function onHide() as Void {
        stopRefresh();
    }

    //! A cover takes seconds to travel, so look again twice after a press rather than
    //! leaving the screen showing the state from before the button was pressed.
    function scheduleRefresh() as Void {
        stopRefresh();
        _refreshesLeft = 2;
        _refresh = new Timer.Timer();
        (_refresh as Timer.Timer).start(method(:onRefreshTick), 4000, true);
    }

    function onRefreshTick() as Void {
        _reader.refresh();
        _refreshesLeft -= 1;
        if (_refreshesLeft <= 0) {
            stopRefresh();
        }
    }

    private function stopRefresh() as Void {
        if (_refresh != null) {
            (_refresh as Timer.Timer).stop();
            _refresh = null;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, (height * 0.09).toNumber(), Graphics.FONT_MEDIUM, title(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var buttonWidth = (width * 0.8).toNumber();
        var buttonHeight = (height * 0.3).toNumber();
        var buttonY = (height * 0.42).toNumber();

        if (_reader.hasEntity()) {
            var state = _reader.stateText();
            if (state instanceof String) {
                dc.setColor(_reader.color(), Graphics.COLOR_TRANSPARENT);
                dc.drawText(width / 2, (height * 0.18).toNumber(), Graphics.FONT_SMALL,
                            state as String,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }

            var doorWidth = (width * 0.15).toNumber();
            var doorHeight = (height * 0.14).toNumber();
            _reader.drawDoor(dc, (width - doorWidth) / 2, (height * 0.24).toNumber(),
                             doorWidth, doorHeight);
        }

        dc.setColor(buttonColor(), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((width - buttonWidth) / 2, buttonY, buttonWidth, buttonHeight, 16);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, buttonY + (buttonHeight / 2), Graphics.FONT_LARGE, buttonLabel(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, (height * 0.85).toNumber(), Graphics.FONT_SMALL, footerText(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function title() as String {
        var name = _reader.getName();
        return name instanceof String ? name as String : _runner.getLabel();
    }

    private function buttonColor() as ColorValue {
        switch (_runner.getState()) {
            case RUN_SENDING:
                return Graphics.COLOR_ORANGE;
            case RUN_FAILED:
                return Graphics.COLOR_DK_RED;
            default:
                return Graphics.COLOR_BLUE;
        }
    }

    //! With a state to read, the button says what the press will do, so one screen both
    //! opens and closes.
    private function buttonLabel() as String {
        switch (_runner.getState()) {
            case RUN_SENDING:
                return "SENDING";
            case RUN_FAILED:
                return "FAILED";
        }
        if (_reader.hasEntity() && _reader.stateText() instanceof String) {
            return _reader.isOpen() ? "CLOSE" : "OPEN";
        }
        return _runner.getState() == RUN_SENT ? "SENT" : "SEND";
    }

    private function footerText() as String {
        switch (_runner.getState()) {
            case RUN_SENDING:
                return "Contacting Home Assistant";
            case RUN_SENT:
                return "Sent at " + _runner.getDetail();
            case RUN_FAILED:
                return _runner.getDetail();
            default:
                return "Press START or tap";
        }
    }
}
