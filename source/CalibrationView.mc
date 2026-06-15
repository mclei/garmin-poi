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

        // Full rotating compass (like the main view) so the user can see the
        // heading respond and verify N points the right way after calibrating.
        drawCompassRing(dc, cx, cy, ring);

        // Calibration instructions in the centre of the compass.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (ring * 0.34).toNumber(), Graphics.FONT_XTINY,
                    "CALIBRATE IN",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (ring * 0.15).toNumber(), Graphics.FONT_TINY,
                    "Settings > System",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy, Graphics.FONT_TINY,
                    "> Compass > Calibrate",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // live heading readout for precise verification
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var hdgText = _have
            ? (_heading.toNumber().toString() + " " + GeoUtils.cardinal(_heading))
            : "--";
        dc.drawText(cx, cy + (ring * 0.22).toNumber(), Graphics.FONT_XTINY,
                    hdgText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Rotating compass ring with N/E/S/W and 45-deg ticks (same as MainView).
    private function drawCompassRing(dc as Dc, cx as Number, cy as Number,
                                     ring as Number) as Void {
        var hdg = _have ? _heading : 0.0;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, ring);
        dc.setPenWidth(1);
        var labels = ["N", "E", "S", "W"];
        for (var deg = 0; deg < 360; deg += 45) {
            var a = Math.toRadians(GeoUtils.normDeg((deg - hdg).toFloat()));
            var sx = Math.sin(a);
            var sy = Math.cos(a);
            if (deg % 90 == 0) {
                var lx = cx + (ring - 18) * sx;
                var ly = cy - (ring - 18) * sy;
                dc.setColor((deg == 0) ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY,
                            Graphics.COLOR_TRANSPARENT);
                dc.drawText(lx.toNumber(), ly.toNumber(), Graphics.FONT_TINY,
                            labels[deg / 90],
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                var x1 = cx + (ring - 8) * sx;
                var y1 = cy - (ring - 8) * sy;
                var x2 = cx + ring * sx;
                var y2 = cy - ring * sy;
                dc.drawLine(x1.toNumber(), y1.toNumber(),
                            x2.toNumber(), y2.toNumber());
            }
        }
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
