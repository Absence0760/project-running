import Toybox.Application;
import Toybox.WatchUi;

// Data-field entry point. A data field has no top-level UI of its own --
// getInitialView returns the single field that Garmin embeds into whichever
// data-screen cell the user assigns it to.
class RunGarminApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [ new GradeAdjustedPaceView() ];
    }
}
