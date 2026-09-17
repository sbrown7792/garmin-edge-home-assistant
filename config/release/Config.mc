import Toybox.Attention;
import Toybox.Lang;

// Release defaults: everything blank so the store build ships no personal data. Users
// fill these in under Garmin Connect > HA Control > Settings.
const HA_BASE_URL = "";
const HA_TOKEN = "";
const STATUS_ENTITY = "";

// Event type every button fires; automations trigger on it and match on the label.
const EVENT_TYPE = "garmin_edge";

// No buttons until the user configures one in settings.
const ACTIONS = [] as Array<Dictionary<Symbol, String>>;

const TEST_ACTION = { :label => "Test ping", :event => "garmin_edge" } as Dictionary<Symbol, String>;

// Feedback tones. TONE_SUCCESS is the long celebratory jingle; these are single beeps.
const SUCCESS_TONE = Attention.TONE_LOUD_BEEP;
const FAILURE_TONE = Attention.TONE_ERROR;

// Arrival data field. Stopping the ride timer within the radius of Home Assistant's
// zone.home fires EVENT_TYPE with this action name. 0 uses the zone's own radius.
const ARRIVE_ACTION = "Arrive";
const ARRIVE_RADIUS = 0;
