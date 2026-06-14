import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.WatchUi;

// Small radius / element cap keep the glance's web response tiny enough for the
// glance memory budget (it only needs nearby places).
const GLANCE_RADIUS = 1500;
const GLANCE_CAP = 20;
const GLANCE_FOV = 45.0;     // pick the nearest place within this cone ahead
const SCROLL_STEP = 4;       // px per 200 ms tick for the marquee
const SCROLL_GAP = 28;       // px gap between marquee repeats
const PICK_TICKS = 5;        // re-pick by heading every Nth tick (~1 s)

// Glance states
const G_NOFIX = 0;
const G_LOADING = 1;
const G_OK = 2;
const G_EMPTY = 3;
const G_ERR = 4;

// Glance-carousel preview for Ahead. When scrolled into view it reads the
// last-known position and runs one compact Overpass query; it then features the
// nearest place in the direction you are facing (compass), and marquee-scrolls
// the name so a long one can be read in full. Self-contained: no PoiModel.
class AheadGlance extends WatchUi.GlanceView {

    private var _state as Number;
    private var _lat as Double;
    private var _lon as Double;
    private var _pending as Boolean;
    private var _opIndex as Number;

    // candidates from the last fetch (parallel arrays, bounded by GLANCE_CAP)
    private var _names as Array<String>;
    private var _bears as Array<Float>;
    private var _dists as Array<Float>;

    // current focused result + compass + marquee state
    private var _name as String;
    private var _dist as Float;
    private var _heading as Float;
    private var _haveHeading as Boolean;
    private var _scroll as Number;
    private var _ticks as Number;
    private var _timer as Timer.Timer?;

    function initialize() {
        GlanceView.initialize();
        _state = G_NOFIX;
        _lat = 0.0;
        _lon = 0.0;
        _pending = false;
        _opIndex = 0;
        _names = [] as Array<String>;
        _bears = [] as Array<Float>;
        _dists = [] as Array<Float>;
        _name = "";
        _dist = 0.0;
        _heading = 0.0;
        _haveHeading = false;
        _scroll = 0;
        _ticks = 0;
        _timer = null;
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTimer), 200, true);
        _timer = t;
        startFetch();
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); _timer = null; }
    }

    // Advance the marquee every tick (smooth scroll), but only re-read the
    // compass and re-pick the featured place about once a second.
    function onTimer() as Void {
        _ticks += 1;
        if (_ticks % PICK_TICKS == 0 && _names.size() > 0) {
            readHeading();
            pickFocused();
        }
        _scroll += SCROLL_STEP;
        WatchUi.requestUpdate();
    }

    private function readHeading() as Void {
        var si = Sensor.getInfo();
        if (si != null && si.heading != null) {
            _heading = GeoUtils.normDeg(Math.toDegrees(si.heading).toFloat());
            _haveHeading = true;
        }
    }

    private function startFetch() as Void {
        if (_pending) { return; }
        var info = Position.getInfo();
        if (info == null || info.position == null) {
            _state = G_NOFIX;
            WatchUi.requestUpdate();
            return;
        }
        var deg = info.position.toDegrees();
        _lat = deg[0].toDouble();
        _lon = deg[1].toDouble();
        _pending = true;
        _state = G_LOADING;
        WatchUi.requestUpdate();
        var opts = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(
            OVERPASS_MIRRORS[_opIndex % OVERPASS_MIRRORS.size()],
            {"data" => buildQuery()}, opts, method(:onResponse));
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        _pending = false;
        if (code == 200 && data instanceof Dictionary) {
            buildCandidates(data["elements"]);
            if (_names.size() > 0) {
                readHeading();
                pickFocused();
            } else {
                _state = G_EMPTY;
            }
        } else {
            _opIndex = (_opIndex + 1) % OVERPASS_MIRRORS.size();
            _state = G_ERR;
        }
        WatchUi.requestUpdate();
    }

    private function buildCandidates(elements) as Void {
        var names = [] as Array<String>;
        var bears = [] as Array<Float>;
        var dists = [] as Array<Float>;
        if (elements instanceof Array) {
            for (var i = 0; i < elements.size(); i++) {
                var el = elements[i];
                if (!(el instanceof Dictionary)) { continue; }
                var geom = el["geometry"];
                if (!(geom instanceof Dictionary)) { continue; }
                var c = geom["coordinates"];
                if (!(c instanceof Array) || c.size() < 2) { continue; }
                var plon = numToD(c[0]);
                var plat = numToD(c[1]);
                if (plat == null || plon == null) { continue; }
                names.add(nameOf(el["tags"]));
                bears.add(GeoUtils.bearingDeg(_lat, _lon, plat, plon));
                dists.add(GeoUtils.distanceM(_lat, _lon, plat, plon));
            }
        }
        _names = names;
        _bears = bears;
        _dists = dists;
    }

    // Nearest within the field-of-view cone; if none (or no compass), nearest
    // overall. Resets the marquee when the featured place changes.
    private function pickFocused() as Void {
        var best = -1;
        var bestD = 1.0e12;
        if (_haveHeading) {
            for (var i = 0; i < _names.size(); i++) {
                var diff = GeoUtils.angleDiff(_bears[i], _heading);
                if (diff < 0) { diff = -diff; }
                if (diff <= GLANCE_FOV && _dists[i] < bestD) {
                    best = i;
                    bestD = _dists[i];
                }
            }
        }
        if (best < 0) {
            bestD = 1.0e12;
            for (var i = 0; i < _names.size(); i++) {
                if (_dists[i] < bestD) { best = i; bestD = _dists[i]; }
            }
        }
        if (best >= 0) {
            if (!_names[best].equals(_name)) { _scroll = 0; }  // restart marquee
            _name = _names[best];
            _dist = _dists[best];
            _state = G_OK;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var fh = dc.getFontHeight(Graphics.FONT_GLANCE);
        var y1 = (h / 2 - fh * 0.55).toNumber();
        var y2 = (h / 2 + fh * 0.55).toNumber();

        // top line: app name + distance of the featured place
        var top = "Ahead";
        if (_state == G_OK) { top += "  " + GeoUtils.formatDistance(_dist); }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, y1, Graphics.FONT_GLANCE, top,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // bottom line: the place name (marquee) or a status message
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (_state == G_OK) {
            drawMarquee(dc, _name, y2, w);
        } else {
            var msg = "Scanning...";
            if (_state == G_NOFIX) { msg = "Waiting for GPS"; }
            else if (_state == G_ERR) { msg = "No connection"; }
            else if (_state == G_EMPTY) { msg = "Nothing nearby"; }
            dc.drawText(0, y2, Graphics.FONT_GLANCE, msg,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Scroll the name leftwards and repeat, so a name wider than the glance can
    // be read in full. Drawn text is clipped to the glance bounds.
    private function drawMarquee(dc as Dc, text as String, y as Number,
                                 w as Number) as Void {
        var tw = dc.getTextWidthInPixels(text, Graphics.FONT_GLANCE);
        if (tw <= w) {
            dc.drawText(0, y, Graphics.FONT_GLANCE, text,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var period = tw + SCROLL_GAP;
        var off = _scroll % period;
        var x = -off;
        dc.drawText(x, y, Graphics.FONT_GLANCE, text,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(x + period, y, Graphics.FONT_GLANCE, text,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function nameOf(tags) as String {
        if (tags instanceof Dictionary) {
            var nm = tags["name"];
            if (nm instanceof String && nm.length() > 0) { return nm; }
            var sub = first(tags["h"], first(tags["to"], tags["a"]));
            if (sub.length() > 0) { return prettify(sub); }
        }
        return "place";
    }

    private function first(a, b) as String {
        if (a instanceof String && a.length() > 0) { return a; }
        if (b instanceof String && b.length() > 0) { return b; }
        return "";
    }

    // Compact Overpass `convert` query honouring the saved category toggles,
    // at a small fixed radius (mirrors PoiModel.buildQuery, trimmed for size).
    private function buildQuery() as String {
        var la = _lat.format("%.5f");
        var lo = _lon.format("%.5f");
        var ar = "(around:" + GLANCE_RADIUS.toString() + "," + la + "," + lo + ");";
        var q = "[out:json][timeout:20];(";
        if (catOn(CAT_MONUMENT)) {
            q += "nwr[historic]" + ar;
        } else {
            if (catOn(CAT_CASTLE)) {
                q += "nwr[historic~\"^(castle|fort|fortress|city_gate|citadel|castle_wall|manor|palace)$\"]" + ar;
            }
            if (catOn(CAT_RUINS)) {
                q += "nwr[historic~\"^(ruins|archaeological_site)$\"]" + ar;
            }
        }
        if (catOn(CAT_VIEWPOINT)) {
            q += "nwr[tourism~\"^(attraction|viewpoint)$\"]" + ar;
        }
        var food = "";
        if (catOn(CAT_RESTAURANT)) { food += "restaurant|"; }
        if (catOn(CAT_CAFE)) { food += "cafe|fast_food|ice_cream|"; }
        if (catOn(CAT_BAR)) { food += "bar|pub|biergarten|"; }
        if (food.length() > 0) {
            food = food.substring(0, food.length() - 1);
            q += "nwr[amenity~\"^(" + food + ")$\"]" + ar;
        }
        if (catOn(CAT_MUSEUM)) {
            q += "nwr[tourism~\"^(museum|gallery|artwork)$\"]" + ar;
        }
        if (catOn(CAT_THEATRE)) {
            q += "nwr[amenity~\"^(theatre|cinema|arts_centre)$\"]" + ar;
        }
        if (catOn(CAT_WORSHIP)) {
            q += "nwr[amenity=place_of_worship]" + ar;
        }
        q += ")->.r;.r convert poi ::id=id(),::geom=center(geom()),"
           + "name=t[\"name\"],h=t[\"historic\"],to=t[\"tourism\"],a=t[\"amenity\"];"
           + "out geom " + GLANCE_CAP.toString() + ";";
        return q;
    }

    private function catOn(cat as Number) as Boolean {
        try {
            var v = Application.Properties.getValue(PoiCat.propKey(cat));
            if (v instanceof Boolean) { return v; }
        } catch (e) {
        }
        return PoiCat.defaultEnabled(cat);
    }

    private function numToD(v) as Double? {
        if (v instanceof Double) { return v; }
        if (v instanceof Float || v instanceof Number || v instanceof Long) {
            return v.toDouble();
        }
        return null;
    }

    private function prettify(s as String) as String {
        var out = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            out += (chars[i] == '_') ? " " : chars[i].toString();
        }
        if (out.length() > 1) {
            out = out.substring(0, 1).toUpper() + out.substring(1, out.length());
        }
        return out;
    }
}
