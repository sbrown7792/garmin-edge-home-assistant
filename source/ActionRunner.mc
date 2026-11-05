import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

enum RunState {
    RUN_READY = 0,
    RUN_SENDING = 1,
    RUN_SENT = 2,
    RUN_FAILED = 3
}

//! Turns one entry of ACTIONS into a web request and tracks how it went.
class ActionRunner {

    private var _action as Dictionary<Symbol, String>;
    private var _state as RunState = RUN_READY;
    private var _detail as String = "";
    private var _watchdog as Timer.Timer?;
    // Waiting out a press sent before the screen was last closed: no answer will come to
    // this run of the app, so the wait ends quietly rather than as a failure.
    private var _inherited as Boolean = false;

    function initialize(action as Dictionary<Symbol, String>) {
        _action = action;
        inheritPending();
    }

    //! Leaving the screen does not take a press back. Garmin Connect may still be holding
    //! it, so a press sent in the last LOST_MS keeps this screen in its waiting state even
    //! after the app is closed and reopened. The time is wall-clock, so it stays right
    //! across an Edge restart, where System.getTimer() would start again from zero.
    private function inheritPending() as Void {
        var since = Application.Storage.getValue(pendingKey());
        if (!(since instanceof Number)) {
            return;
        }
        var ageMs = (Time.now().value() - (since as Number)) * 1000;
        if (ageMs < 0 || ageMs >= LOST_MS) {
            Application.Storage.deleteValue(pendingKey());
            return;
        }
        _state = RUN_SENDING;
        _detail = "Last press still waiting";
        _inherited = true;
        _watchdog = new Timer.Timer();
        (_watchdog as Timer.Timer).start(method(:onLost), LOST_MS - ageMs, false);
    }

    private function pendingKey() as String {
        return "pending:" + getLabel();
    }

    function getLabel() as String {
        var label = _action[:label];
        return label instanceof String ? label : "Action";
    }

    function getEntity() as String {
        var entity = _action[:entity];
        return entity instanceof String ? entity as String : "";
    }

    function getState() as RunState {
        return _state;
    }

    function getDetail() as String {
        return _detail;
    }

    function run() as Void {
        // Includes the "Waiting for phone" stretch. A press that times out on screen can
        // still be delivered later, and with cover.toggle a second queued press would
        // open the door and then shut it again.
        if (_state == RUN_SENDING) {
            return;
        }

        var url = buildUrl();
        if (url == null) {
            fail("Action not configured");
            return;
        }

        _state = RUN_SENDING;
        _detail = "";
        WatchUi.requestUpdate();

        Application.Storage.setValue(pendingKey(), Time.now().value());
        startWatchdog();

        Communications.makeWebRequest(url, buildBody(), {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => buildHeaders(),
            :responseType => expectedResponseType()
        }, method(:onResponse));
    }

    function onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        stopWatchdog();
        Application.Storage.deleteValue(pendingKey());
        if (responseCode >= 200 && responseCode < 300) {
            _state = RUN_SENT;
            _detail = clockString();
            Application.Storage.setValue("lastAction", getLabel() + " " + _detail);
        } else {
            _state = RUN_FAILED;
            _detail = describe(responseCode);
            Application.Storage.setValue("lastAction", getLabel() + " failed");
        }
        alert(_state == RUN_SENT);
        WatchUi.requestUpdate();
    }

    private function buildUrl() as String? {
        var raw = _action[:url];
        if (raw instanceof String) {
            return raw;
        }
        var base = AppConfig.baseUrl();
        if (base.length() == 0) {
            return null;
        }
        var event = _action[:event];
        if (event instanceof String) {
            return base + "/api/events/" + event;
        }
        var webhook = _action[:webhook];
        if (webhook instanceof String) {
            return base + "/api/webhook/" + webhook;
        }
        var service = _action[:service];
        if (service instanceof String) {
            var dot = service.find(".");
            if (dot == null) {
                return null;
            }
            var domain = service.substring(0, dot);
            var name = service.substring(dot + 1, service.length());
            return base + "/api/services/" + domain + "/" + name;
        }
        return null;
    }

    //! The phone relay parses the reply by the server's own Content-Type, whatever we
    //! ask for, and it cannot represent a top-level JSON array — which is exactly what
    //! Home Assistant returns from /api/services, hence -400 even though the call ran.
    //! /api/events answers with a small JSON object, which survives the trip.
    private function expectedResponseType() as Communications.HttpResponseContentType {
        if (_action[:event] instanceof String) {
            return Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON;
        }
        return Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN;
    }

    //! Without a watchdog, a relay that drops a reply would leave SENDING on screen for
    //! ever. But silence at WAIT_MS is not failure either: the relay can hold a request
    //! for a minute or more before answering (seen: 77 s, while the phone could not
    //! reach the server). So the press stays pending and says so, and only at LOST_MS
    //! is it written off.
    private const WAIT_MS = 20000;
    private const LOST_MS = 120000;

    private function startWatchdog() as Void {
        stopWatchdog();
        _watchdog = new Timer.Timer();
        (_watchdog as Timer.Timer).start(method(:onTimeout), WAIT_MS, false);
    }

    private function stopWatchdog() as Void {
        if (_watchdog != null) {
            (_watchdog as Timer.Timer).stop();
            _watchdog = null;
        }
    }

    function onTimeout() as Void {
        stopWatchdog();
        if (_state == RUN_SENDING) {
            _detail = "Waiting for phone";
            WatchUi.requestUpdate();
            _watchdog = new Timer.Timer();
            (_watchdog as Timer.Timer).start(method(:onLost), LOST_MS - WAIT_MS, false);
        }
    }

    function onLost() as Void {
        stopWatchdog();
        Application.Storage.deleteValue(pendingKey());
        if (_state != RUN_SENDING) {
            return;
        }
        if (_inherited) {
            // The press belonged to an earlier run of the app; its fate is unknown here,
            // and the state line shows whether the door moved. Just allow presses again.
            _inherited = false;
            _state = RUN_READY;
            _detail = "";
        } else {
            _state = RUN_FAILED;
            _detail = "No reply in 2 min";
            alert(false);
        }
        WatchUi.requestUpdate();
    }

    private function buildBody() as Dictionary<Object, Object> {
        var body = {} as Dictionary<Object, Object>;
        if (_action[:event] instanceof String) {
            body["action"] = getLabel();
            var target = _action[:entity];
            if (target instanceof String) {
                body["entity_id"] = target;
            }
            return body;
        }
        if (_action[:service] instanceof String) {
            var entity = _action[:entity];
            if (entity instanceof String) {
                body["entity_id"] = entity;
            }
            return body;
        }
        body["action"] = getLabel();
        body["source"] = "garmin";
        return body;
    }

    private function buildHeaders() as Dictionary<Object, Object> {
        var headers = {} as Dictionary<Object, Object>;
        headers["Content-Type"] = Communications.REQUEST_CONTENT_TYPE_JSON;
        var token = AppConfig.token();
        var needsAuth = _action[:service] instanceof String || _action[:event] instanceof String;
        if (needsAuth && token.length() > 0) {
            headers["Authorization"] = "Bearer " + token;
        }
        return headers;
    }

    private function fail(message as String) as Void {
        _state = RUN_FAILED;
        _detail = message;
        WatchUi.requestUpdate();
    }

    private function alert(success as Boolean) as Void {
        if (Attention has :playTone) {
            Attention.playTone(success ? SUCCESS_TONE : FAILURE_TONE);
        }
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(75, success ? 200 : 600)] as Array<VibeProfile>);
        }
    }

    private function clockString() as String {
        var now = System.getClockTime();
        return Lang.format("$1$:$2$", [now.hour, now.min.format("%02d")]);
    }

    private function describe(code as Number) as String {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return "Phone not connected";
        }
        if (code == Communications.BLE_HOST_TIMEOUT || code == Communications.BLE_SERVER_TIMEOUT ||
            code == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "Timed out";
        }
        if (code == Communications.SECURE_CONNECTION_REQUIRED) {
            return "HTTPS required";
        }
        if (code == 401 || code == 403) {
            return "Check token";
        }
        if (code == 404) {
            return "Not found on server";
        }
        if (code == Communications.REQUEST_CONNECTION_DROPPED) {
            return "Link dropped";
        }
        if (code == Communications.BLE_QUEUE_FULL) {
            return "Queue full";
        }
        return "Error " + code.toString();
    }
}
