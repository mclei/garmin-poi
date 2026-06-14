import Toybox.Lang;
import Toybox.WatchUi;

// Input mapping for the compass screen.
//   Tap, or Start/Enter button .. detail page of the shown POI
//   Swipe in from right edge .... Filters menu (settings)
//   Swipe up .................... Nearby POI list
//   Long-press (where supported)  Filters menu
//   Back ........................ exit
class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _model as PoiModel;

    function initialize(model as PoiModel) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    // Primary action button (Start/Enter) and screen tap both open the detail
    // page of the shown POI. Settings are reached by the right-edge swipe.
    function onSelect() as Boolean {
        return openDetail();
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return openDetail();
    }

    private function openDetail() as Boolean {
        var f = _model.focusedPoi();
        if (f != null) {
            PoiUi.pushDetail(_model, f);
        }
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var dir = evt.getDirection();
        if (dir == WatchUi.SWIPE_LEFT) {
            // finger drags in from the right edge toward the left -> settings
            PoiUi.pushFilterMenu(_model);
            return true;
        }
        if (dir == WatchUi.SWIPE_UP) {
            PoiUi.pushPoiList(_model);
            return true;
        }
        return false;
    }

    // Long-press menu behavior, on devices/firmware that emit it -> settings
    function onMenu() as Boolean {
        PoiUi.pushFilterMenu(_model);
        return true;
    }
}
