import Toybox.Lang;
import Toybox.WatchUi;

class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _model as PoiModel;

    function initialize(model as PoiModel) {
        BehaviorDelegate.initialize();
        _model = model;
    }

    function onMenu() as Boolean {
        PoiUi.pushFilterMenu(_model);
        return true;
    }

    function onSelect() as Boolean {
        PoiUi.pushPoiList(_model);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        PoiUi.pushPoiList(_model);
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        if (evt.getDirection() == WatchUi.SWIPE_UP) {
            PoiUi.pushPoiList(_model);
            return true;
        }
        return false;
    }
}
