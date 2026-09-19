import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//! Colours that follow the Edge's own light/dark setting, so the glance is not a black
//! rectangle in a white system at midday. The device switches by sunset or on a
//! schedule, and reports the current state through DeviceSettings.isNightModeEnabled.
(:glance)
module Theme {

    //! isNightModeEnabled arrived in API level 4.1.2, and every Edge this app targets
    //! has it. The manifest allows 4.0.0, so where it is missing fall back to dark,
    //! which is what these screens drew before and is right at night, when a bike
    //! computer is most often read.
    function isDark() as Boolean {
        var settings = System.getDeviceSettings();
        if (settings has :isNightModeEnabled) {
            return settings.isNightModeEnabled;
        }
        return true;
    }

    function background() as ColorValue {
        return isDark() ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
    }

    function text() as ColorValue {
        return isDark() ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
    }

    //! For footers and other secondary lines: legible, but a step back from the title.
    function dimText() as ColorValue {
        return isDark() ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
    }

    //! State colours have to carry meaning on either background. Bright green and yellow
    //! read well on black and disappear on white, so the light variants are darker.
    function closedColor() as ColorValue {
        return isDark() ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GREEN;
    }

    //! There is no dark yellow constant, and yellow on white is barely there, so light
    //! mode uses an amber of its own. Open stays orange in both, which keeps one colour
    //! meaning one thing whatever the time of day.
    function movingColor() as ColorValue {
        return isDark() ? Graphics.COLOR_YELLOW : 0xB36B00;
    }

    function openColor() as ColorValue {
        return Graphics.COLOR_ORANGE;
    }

    function unknownColor() as ColorValue {
        return isDark() ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
    }
}
