import Toybox.Lang;
import Toybox.System;

//! HA Control's diagnostics: one "HH:MM:SS text" line per event, written to
//! Garmin/Apps/LOGS/HaControl.TXT. The device only writes System.println output for a
//! sideloaded app when that file already exists, which `./install.sh app` creates;
//! without it these calls cost next to nothing. Never log the token or the server name.
(:glance)
module Log {

    function line(text as String) as Void {
        var now = System.getClockTime();
        System.println(Lang.format("$1$:$2$:$3$ $4$",
            [now.hour.format("%02d"), now.min.format("%02d"), now.sec.format("%02d"), text]));
    }

    //! What the Edge itself believes about its links, logged with every request, so a
    //! failure can be lined up against the phone dropping away. bt is the Bluetooth
    //! ConnectionState: 0 not set up, 1 set up but out of range, 2 connected.
    function links() as String {
        var settings = System.getDeviceSettings();
        var text = "phone=" + (settings.phoneConnected ? "yes" : "no");
        if (settings has :connectionAvailable) {
            text += " link=" + (settings.connectionAvailable ? "yes" : "no");
        }
        if (settings has :connectionInfo) {
            var bluetooth = settings.connectionInfo[:bluetooth];
            if (bluetooth != null) {
                text += " bt=" + (bluetooth as System.ConnectionInfo).state.toString();
            }
        }
        return text;
    }

    //! The body of a failed reply, which is sometimes the only hint at what failed.
    //! Shortened so a large reply cannot exhaust the glance's memory.
    function brief(data as Object?) as String {
        if (data == null) {
            return "none";
        }
        var text = data.toString();
        return text.length() > 80 ? text.substring(0, 80) + "..." : text;
    }
}
