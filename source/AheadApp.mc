import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class AheadApp extends Application.AppBase {

    private var _model as PoiModel?;

    function initialize() {
        AppBase.initialize();
    }

    function getModel() as PoiModel {
        if (_model == null) {
            _model = new PoiModel();
        }
        return _model as PoiModel;
    }

    function onStart(state as Dictionary?) as Void {
        getModel().start();
    }

    function onStop(state as Dictionary?) as Void {
        getModel().stop();
    }

    function onSettingsChanged() as Void {
        getModel().reloadSettings();
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        var model = getModel();
        return [new MainView(model), new MainDelegate(model)];
    }

    // Glance carousel preview. It fetches on its own (last-known position +
    // one small POI query) when shown - independent of the full app/model.
    function getGlanceView() {
        return [new AheadGlance()];
    }
}
