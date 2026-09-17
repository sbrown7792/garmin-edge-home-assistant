import Toybox.Lang;
import Toybox.WatchUi;

//! Selecting an item opens its screen without firing it. The screen shows the current
//! state, and the button there is the deliberate press.
class ActionMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as MenuItem) as Void {
        var index = item.getId();
        if (!(index instanceof Number)) {
            return;
        }

        var runner = new ActionRunner(AppConfig.actions()[index as Number]);
        var view = new ActionView(runner);
        WatchUi.pushView(view, new ActionDelegate(runner, view), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
