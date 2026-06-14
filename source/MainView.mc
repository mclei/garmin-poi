import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;
import Toybox.WatchUi;

// Compass/radar screen: rotating ring, POI dots, focused POI with arrow.
class MainView extends WatchUi.View {

    private var _model as PoiModel;
    private var _timer as Timer.Timer?;

    function initialize(model as PoiModel) {
        View.initialize();
        _model = model;
        _timer = null;
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 200, true);
        _timer = t;
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        _model.tick();
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

        drawCompassRing(dc, cx, cy, ring);

        if (_model.lat == null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 12, Graphics.FONT_MEDIUM,
                        WatchUi.loadResource(Rez.Strings.WaitGps),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, cy + 18, Graphics.FONT_XTINY,
                        WatchUi.loadResource(Rez.Strings.Subtitle),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            drawStatus(dc, cx, cy, ring, w, h);
            return;
        }

        drawPoiDots(dc, cx, cy, ring);

        var f = _model.focusedPoi();
        if (f != null) {
            drawFocused(dc, cx, cy, ring, f);
        } else {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_SMALL,
                        WatchUi.loadResource(Rez.Strings.NoPois),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        drawStatus(dc, cx, cy, ring, w, h);
    }

    private function drawCompassRing(dc as Dc, cx as Number, cy as Number,
                                     ring as Number) as Void {
        var hdg = _model.headingDeg;
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
                if (deg == 0) {
                    dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                } else {
                    dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                }
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

    private function drawPoiDots(dc as Dc, cx as Number, cy as Number,
                                 ring as Number) as Void {
        var hdg = _model.headingDeg;
        var vis = _model.visible;
        var n = vis.size();
        if (n > 30) { n = 30; }
        // draw farthest first so near dots end up on top
        for (var i = n - 1; i >= 0; i--) {
            var p = vis[i];
            var rr = p.distance / POI_RANGE;
            if (rr > 1.0) { rr = 1.0; }
            rr = Math.sqrt(rr).toFloat();
            var rpx = (ring - 28) * rr;
            var a = Math.toRadians(GeoUtils.normDeg(p.bearing - hdg));
            var x = cx + rpx * Math.sin(a);
            var y = cy - rpx * Math.cos(a);
            dc.setColor(PoiCat.color(p.category), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x.toNumber(), y.toNumber(), 4);
        }
    }

    private function drawFocused(dc as Dc, cx as Number, cy as Number,
                                 ring as Number, f as Poi) as Void {
        var hdg = _model.headingDeg;
        var rel = GeoUtils.angleDiff(f.bearing, hdg);
        var absRel = (rel < 0) ? -rel : rel;
        var locked = (_model.targetPoi != null);

        // direction arrow
        var col = Graphics.COLOR_LT_GRAY;
        if (absRel <= 20.0) {
            col = Graphics.COLOR_GREEN;
        } else if (absRel <= 60.0) {
            col = Graphics.COLOR_YELLOW;
        }
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        drawTriangle(dc, cx.toFloat(), (cy - ring * 0.45).toFloat(),
                     GeoUtils.normDeg(rel), ring * 0.17);

        if (locked) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (ring * 0.24).toNumber(), Graphics.FONT_XTINY,
                        "LOCKED",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        drawFocusedPoi(dc, cx, cy, ring, f);
    }

    private function drawFocusedPoi(dc as Dc, cx as Number, cy as Number,
                                    ring as Number, f as Poi) as Void {
        // name
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var name = fitText(dc, f.name, Graphics.FONT_MEDIUM, (ring * 1.7).toNumber());
        dc.drawText(cx, cy - (ring * 0.10).toNumber(), Graphics.FONT_MEDIUM, name,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // distance (well below the name so the tall number font can't overlap)
        dc.drawText(cx, cy + (ring * 0.22).toNumber(), Graphics.FONT_NUMBER_MILD,
                    GeoUtils.formatDistance(f.distance),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // detail: subtype / category
        dc.setColor(PoiCat.color(f.category), Graphics.COLOR_TRANSPARENT);
        var detail = f.detail;
        if (detail.length() == 0) {
            detail = PoiCat.shortName(f.category);
        }
        detail = fitText(dc, detail, Graphics.FONT_XTINY, (ring * 1.6).toNumber());
        dc.drawText(cx, cy + (ring * 0.42).toNumber(), Graphics.FONT_XTINY, detail,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawStatus(dc as Dc, cx as Number, cy as Number,
                                ring as Number, w as Number, h as Number) as Void {
        var hdg = _model.headingDeg;
        var approx = (_model.posApprox && _model.lat != null) ? "~" : "";
        var s = "";
        var os = _model.oneShotCategory();
        if (os >= 0) { s += "only " + PoiCat.shortName(os) + " | "; }
        s += approx + hdg.toNumber().toString() + " "
           + GeoUtils.cardinal(hdg) + " | ";
        if (_model.lat == null) {
            s += "no fix";
        } else if (_model.poiStatus == STATUS_LOADING) {
            s += WatchUi.loadResource(Rez.Strings.Loading);
        } else if (_model.poiStatus == STATUS_ERROR) {
            s += "POI err " + _model.poiError.toString();
        } else {
            s += _model.visible.size().toString() + " POI";
        }
        // square display: use the margin below the ring if there is one
        var bottomMargin = h - (cy + ring);
        var sy = (bottomMargin >= 20) ? (cy + ring + bottomMargin / 2)
                                      : (cy + ring - 18);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, sy, Graphics.FONT_XTINY, s,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Filled triangle pointing at angleDeg (0 = up, clockwise), centered on x,y
    private function drawTriangle(dc as Dc, x as Float, y as Float,
                                  angleDeg as Float, size as Float) as Void {
        var a = Math.toRadians(angleDeg);
        var s = Math.sin(a);
        var c = Math.cos(a);
        var pts = [
            [0.0, -size],
            [0.62 * size, 0.55 * size],
            [0.0, 0.22 * size],
            [-0.62 * size, 0.55 * size]
        ];
        var poly = [] as Array< Array<Number> >;
        for (var i = 0; i < pts.size(); i++) {
            var px = pts[i][0];
            var py = pts[i][1];
            poly.add([
                (x + px * c - py * s).toNumber(),
                (y + px * s + py * c).toNumber()
            ]);
        }
        dc.fillPolygon(poly);
    }

    private function fitText(dc as Dc, text as String, font as Graphics.FontType,
                             maxW as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxW) {
            return text;
        }
        var t = text;
        while (t.length() > 2
               && dc.getTextWidthInPixels(t + "..", font) > maxW) {
            t = t.substring(0, t.length() - 1);
        }
        return t + "..";
    }
}
