import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.WatchUi;

// Connect IQ apps cannot trigger the system compass calibration (apps can only
// read the heading), so this screen points the user to the watch's built-in
// calibration and shows the live heading so they can verify the result after.
class CalibrationView extends WatchUi.View {

    private var _model as PoiModel;
    private var _heading as Float;
    private var _have as Boolean;
    private var _timer as Timer.Timer?;

    function initialize(model as PoiModel) {
        View.initialize();
        _model = model;
        _heading = 0.0;
        _have = false;
        _timer = null;
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 200, true);
        _timer = t;
        onTick();
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); _timer = null; }
        if (_have) { _model.headingDeg = _heading; }
    }

    function onTick() as Void {
        var si = Sensor.getInfo();
        if (si != null && si.heading != null) {
            _heading = GeoUtils.normDeg(Math.toDegrees(si.heading).toFloat());
            _have = true;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var ring = ((w < h) ? w : h) / 2 - 10;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // title
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (ring * 0.62).toNumber(), Graphics.FONT_XTINY,
                    "CALIBRATE COMPASS",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // the app can't do it - point to the system calibration
        dc.drawText(cx, cy - (ring * 0.42).toNumber(), Graphics.FONT_XTINY,
                    "Do it in watch settings:",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (ring * 0.22).toNumber(), Graphics.FONT_TINY,
                    "Settings > System >",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy - (ring * 0.06).toNumber(), Graphics.FONT_TINY,
                    "Compass > Calibrate",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // live heading so the result can be verified after calibrating
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (ring * 0.18).toNumber(), Graphics.FONT_XTINY,
                    "heading now",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var hdgText = _have
            ? (_heading.toNumber().toString() + " " + GeoUtils.cardinal(_heading))
            : "--";
        dc.drawText(cx, cy + (ring * 0.38).toNumber(), Graphics.FONT_NUMBER_MILD,
                    hdgText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class CalibrationDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
