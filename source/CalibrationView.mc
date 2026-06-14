import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.WatchUi;

// Compass-calibration helper. Connect IQ can't trigger the system magnetometer
// calibration, but it recalibrates automatically as the watch is moved through
// varied orientations - so this screen guides the figure-8 motion and shows the
// live heading so you can watch it settle and confirm it points the right way.
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
        t.start(method(:onTick), 150, true);
        _timer = t;
        onTick();
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); _timer = null; }
        // Hand the freshly-calibrated heading back to the main model.
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
        dc.drawText(cx, cy - (ring * 0.78).toNumber(), Graphics.FONT_XTINY,
                    "COMPASS",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // compass dial: a small ring with a North marker that rotates with you
        var dialR = (ring * 0.34).toNumber();
        var dy = cy - (ring * 0.30).toNumber();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, dy, dialR);
        dc.setPenWidth(1);
        var a = Math.toRadians(GeoUtils.normDeg(-_heading));   // North relative to heading
        var nx = cx + (dialR - 10) * Math.sin(a);
        var ny = dy - (dialR - 10) * Math.cos(a);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(nx.toNumber(), ny.toNumber(), Graphics.FONT_TINY, "N",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // live heading readout
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var hdgText = _have
            ? (_heading.toNumber().toString() + " " + GeoUtils.cardinal(_heading))
            : "--";
        dc.drawText(cx, cy + (ring * 0.10).toNumber(), Graphics.FONT_NUMBER_MILD,
                    hdgText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // instruction
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (ring * 0.40).toNumber(), Graphics.FONT_XTINY,
                    "Wave in a figure-8",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + (ring * 0.55).toNumber(), Graphics.FONT_XTINY,
                    "until N points north",
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
