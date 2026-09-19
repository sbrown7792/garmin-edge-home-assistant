import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class HaApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    //! The Edge flips between light and dark while an app is open — at sunset, or when
    //! the rider changes the setting. Redraw so the colours follow it straight away
    //! rather than at the next state refresh.
    function onNightModeChanged() as Void {
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var actions = AppConfig.actions();
        if (actions.size() > 1) {
            var menu = new WatchUi.Menu2({ :title => "Home Assistant" });
            for (var i = 0; i < actions.size(); i++) {
                var label = actions[i][:label];
                menu.addItem(new WatchUi.MenuItem(
                    label instanceof String ? label : "Action", null, i, null));
            }
            return [menu, new ActionMenuDelegate()];
        }

        var runner = new ActionRunner(actions.size() == 1 ? actions[0] : {});
        var view = new ActionView(runner);
        return [view, new ActionDelegate(runner, view)];
    }

    (:glance)
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new HaGlanceView()];
    }
}
