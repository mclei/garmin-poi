import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

// Small radius / element cap keep the glance's web response tiny enough for the
// glance memory budget (it only needs the nearest place).
const GLANCE_RADIUS = 1500;
const GLANCE_CAP = 20;

// Glance states
const G_NOFIX = 0;
const G_LOADING = 1;
const G_OK = 2;
const G_EMPTY = 3;
const G_ERR = 4;

// Glance-carousel preview for Ahead. When scrolled into view it reads the
// last-known position and runs one compact Overpass query, then shows the
// nearest place. Self-contained: it does not touch the full PoiModel.
class AheadGlance extends WatchUi.GlanceView {

    private var _state as Number;
    private var _name as String;
    private var _dist as Float;
    private var _count as Number;
    private var _lat as Double;
    private var _lon as Double;
    private var _pending as Boolean;
    private var _opIndex as Number;

    function initialize() {
        GlanceView.initialize();
        _state = G_NOFIX;
        _name = "";
        _dist = 0.0;
        _count = 0;
        _lat = 0.0;
        _lon = 0.0;
        _pending = false;
        _opIndex = 0;
    }

    // Fetch each time the glance scrolls into view.
    function onShow() as Void {
        startFetch();
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
            findNearest(data["elements"]);
        } else {
            _opIndex = (_opIndex + 1) % OVERPASS_MIRRORS.size();
            _state = G_ERR;
        }
        WatchUi.requestUpdate();
    }

    private function findNearest(elements) as Void {
        var bestD = 1.0e12;
        var bestName = "";
        var n = 0;
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
                n++;
                var d = GeoUtils.distanceM(_lat, _lon, plat, plon);
                if (d < bestD) {
                    bestD = d;
                    bestName = nameOf(el["tags"]);
                }
            }
        }
        _count = n;
        if (n > 0) {
            _name = bestName;
            _dist = bestD.toFloat();
            _state = G_OK;
        } else {
            _state = G_EMPTY;
        }
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

    function onUpdate(dc as Dc) as Void {
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h / 2 - dc.getFontHeight(Graphics.FONT_GLANCE),
                    Graphics.FONT_GLANCE, "Ahead",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var value;
        if (_state == G_LOADING) {
            value = "Scanning...";
        } else if (_state == G_NOFIX) {
            value = "Waiting for GPS";
        } else if (_state == G_ERR) {
            value = "No connection";
        } else if (_state == G_EMPTY) {
            value = "Nothing nearby";
        } else {
            value = _name + "  " + GeoUtils.formatDistance(_dist);
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h / 2 + dc.getFontHeight(Graphics.FONT_GLANCE) / 2,
                    Graphics.FONT_GLANCE, value,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
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
