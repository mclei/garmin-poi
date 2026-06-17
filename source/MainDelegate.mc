import Toybox.Lang;
import Toybox.WatchUi;

// Input mapping for the compass screen.
//   Tap, or Start/Enter button .. detail page of the shown POI
//   Swipe in from right edge .... Filters menu (settings)
//   Swipe up .................... Nearby POI list
//   Swipe down .................. Quick "show only one category" (one-shot)
//   Long-press (where supported)  Filters menu
//   Back ........................ exit
class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _model as PoiModel;
    private var _view as MainView;

    function initialize(model as PoiModel, view as MainView) {
        BehaviorDelegate.initialize();
        _model = model;
        _view = view;
    }

    // Primary action button (Start/Enter) and screen tap both open the detail
    // page of the shown POI. Settings are reached by the right-edge swipe.
    // Physical Start/Enter button: no touch coordinates, so on the acquiring
    // screen it adopts the last-known fix directly (a no-op if none cached).
    function onSelect() as Boolean {
        if (_model.lat == null) {
            _model.useLastKnown();
            WatchUi.requestUpdate();
            return true;
        }
        return openDetail();
    }

    // Touch: on the acquiring screen only act when the tap lands on (or near)
    // the "Use last known" button; taps elsewhere are ignored. Once positioned,
    // a tap anywhere opens the focused POI's detail page.
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (_model.lat == null) {
            var c = evt.getCoordinates();
            if (c != null && c.size() >= 2 && _view.lastKnownHit(c[0], c[1])) {
                _model.useLastKnown();
                WatchUi.requestUpdate();
            }
            return true;
        }
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
        if (dir == WatchUi.SWIPE_DOWN) {
            PoiUi.pushQuickMenu(_model);
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
