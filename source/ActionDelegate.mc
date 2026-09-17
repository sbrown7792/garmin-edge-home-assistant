import Toybox.Lang;
import Toybox.WatchUi;

class ActionDelegate extends WatchUi.BehaviorDelegate {

    private var _runner as ActionRunner;
    private var _view as ActionView?;

    function initialize(runner as ActionRunner, view as ActionView?) {
        BehaviorDelegate.initialize();
        _runner = runner;
        _view = view;
    }

    function onSelect() as Boolean {
        press();
        return true;
    }

    function onTap(event as ClickEvent) as Boolean {
        press();
        return true;
    }

    private function press() as Void {
        _runner.run();
        if (_view != null) {
            (_view as ActionView).scheduleRefresh();
        }
    }
}
