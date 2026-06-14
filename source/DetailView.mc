import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Scrollable detail page for one POI / aircraft. Pulls richer data on demand
// (full OSM tags for places; type + route for aircraft) and word-wraps it.
class DetailView extends WatchUi.View {

    private var _model as PoiModel;
    private var _poi as Poi;
    private var _scroll as Number;
    private var _maxScroll as Number;
    private var _timer as Timer.Timer?;

    function initialize(model as PoiModel, poi as Poi) {
        View.initialize();
        _model = model;
        _poi = poi;
        _scroll = 0;
        _maxScroll = 0;
        _timer = null;
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 500, true);
        _timer = t;
        onTick();
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) { t.stop(); _timer = null; }
    }

    function onTick() as Void {
        var done = false;
        if (_poi.category == CAT_AIRCRAFT) {
            _model.resolveAircraftFor(_poi);
            var typeDone = (_poi.icao24.length() == 0)
                         || (_model.aircraftType(_poi.icao24) != null);
            var routeDone = (_poi.name.length() == 0)
                          || (_model.aircraftRoute(_poi.name) != null);
            done = typeDone && routeDone;
        } else {
            _model.requestPoiDetail(_poi);
            done = (_model.poiDetail(_poi) != null);
        }
        if (done) {
            var t = _timer;
            if (t != null) { t.stop(); _timer = null; }
        }
        WatchUi.requestUpdate();
    }

    function scrollBy(dy as Number) as Void {
        _scroll += dy;
        if (_scroll > _maxScroll) { _scroll = _maxScroll; }
        if (_scroll < 0) { _scroll = 0; }
        WatchUi.requestUpdate();
    }

    function toggleTarget() as Void {
        if (_model.targetPoi == _poi) {
            _model.targetPoi = null;
        } else {
            _model.targetPoi = _poi;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var margin = (w * 0.08).toNumber();
        var maxW = w - 2 * margin;

        var blocks = buildBlocks();

        // Measure total height first so we can clamp scrolling.
        var total = 8;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            var fh = dc.getFontHeight(b[1]);
            var lines = wrapText(dc, b[0], b[1], maxW);
            total += lines.size() * fh + 2;
        }
        total += 8;
        _maxScroll = total - h;
        if (_maxScroll < 0) { _maxScroll = 0; }
        if (_scroll > _maxScroll) { _scroll = _maxScroll; }

        // Draw.
        var y = 8 - _scroll;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            var font = b[1];
            var fh = dc.getFontHeight(font);
            var lines = wrapText(dc, b[0], font, maxW);
            for (var j = 0; j < lines.size(); j++) {
                if (y + fh > 0 && y < h) {
                    dc.setColor(b[2], Graphics.COLOR_TRANSPARENT);
                    dc.drawText(margin, y, font, lines[j], Graphics.TEXT_JUSTIFY_LEFT);
                }
                y += fh + 2;
            }
        }

        drawScrollbar(dc, w, h, total);
    }

    private function drawScrollbar(dc as Dc, w as Number, h as Number,
                                   total as Number) as Void {
        if (_maxScroll <= 0) { return; }
        var barH = (h * h) / total;
        if (barH < 16) { barH = 16; }
        var trackH = h - barH;
        var pos = (trackH * _scroll) / _maxScroll;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(w - 4, pos, 3, barH);
    }

    // Build display blocks: each is [text, font, color].
    private function buildBlocks() as Array {
        var b = [] as Array;
        if (_poi.category == CAT_AIRCRAFT) {
            buildAircraftBlocks(b);
        } else {
            buildPoiBlocks(b);
        }
        // common footer
        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);
        var locked = (_model.targetPoi == _poi) ? "locked" : "not locked";
        b.add(["START: lock/unlock target (" + locked + ")",
               Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        b.add(["Swipe / buttons to scroll, BACK to close",
               Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        return b;
    }

    private function buildPoiBlocks(b as Array) as Void {
        b.add([_poi.name, Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE]);
        b.add([_poi.detail, Graphics.FONT_XTINY, PoiCat.color(_poi.category)]);
        b.add([GeoUtils.formatDistance(_poi.distance) + "  "
               + _poi.bearing.toNumber().toString() + " deg "
               + GeoUtils.cardinal(_poi.bearing),
               Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY]);
        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);

        var tags = _model.poiDetail(_poi);
        if (tags == null) {
            b.add(["Loading details...", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        } else {
            var n0 = b.size();
            addField(b, "", tagStr(tags, "description"));
            var addr = joinAddr(tags);
            addField(b, "Address", addr);
            addField(b, "Hours", tagStr(tags, "opening_hours"));
            addField(b, "Cuisine", tagStr(tags, "cuisine"));
            var phone = tagStr(tags, "phone");
            if (phone.length() == 0) { phone = tagStr(tags, "contact:phone"); }
            addField(b, "Phone", phone);
            var web = tagStr(tags, "website");
            if (web.length() == 0) { web = tagStr(tags, "contact:website"); }
            addField(b, "Web", web);
            addField(b, "Wikipedia", tagStr(tags, "wikipedia"));
            addField(b, "Elevation", tagStr(tags, "ele"));
            if (b.size() == n0) {
                b.add(["No extra details available",
                       Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
            }
        }
        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);
        b.add([_poi.lat.format("%.5f") + ", " + _poi.lon.format("%.5f"),
               Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
    }

    private function buildAircraftBlocks(b as Array) as Void {
        b.add([_poi.name, Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE]);

        var fr = _model.flightInfo(_poi.name);
        if (fr != null) {
            addField(b, "From", airportLine(fr["origin"]));
            addField(b, "To", airportLine(fr["destination"]));
        } else if (_poi.name.length() == 0) {
            b.add(["No callsign", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        } else if (_model.aircraftRoute(_poi.name) == null) {
            b.add(["Resolving route...", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        } else {
            b.add(["Route unknown", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        }
        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);

        var ac = _model.aircraftInfo(_poi.icao24);
        if (ac != null) {
            var type = tagStr(ac, "type");
            var manuf = tagStr(ac, "manufacturer");
            if (manuf.length() > 0) { type = manuf + " " + type; }
            addField(b, "Type", type);
            addField(b, "ICAO type", tagStr(ac, "icao_type"));
            addField(b, "Operator", tagStr(ac, "registered_owner"));
            addField(b, "Reg.", tagStr(ac, "registration"));
            addField(b, "Country", tagStr(ac, "registered_owner_country_name"));
        } else if (_poi.icao24.length() > 0
                   && _model.aircraftType(_poi.icao24) == null) {
            b.add(["Resolving type...", Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
        }
        b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);

        addField(b, "Now", _poi.detail);   // altitude, speed
        if (_poi.track != null) {
            addField(b, "Heading", (_poi.track as Float).toNumber().toString() + " deg");
        }
        addField(b, "Distance", GeoUtils.formatDistance(_poi.distance) + " "
                 + GeoUtils.cardinal(_poi.bearing));
    }

    private function addField(b as Array, label as String, value as String) as Void {
        if (value == null || value.length() == 0) { return; }
        var text = (label.length() > 0) ? (label + ": " + value) : value;
        b.add([text, Graphics.FONT_XTINY, Graphics.COLOR_WHITE]);
    }

    private function tagStr(d as Dictionary, key as String) as String {
        var v = d[key];
        return (v instanceof String) ? v : "";
    }

    private function joinAddr(tags as Dictionary) as String {
        var street = tagStr(tags, "addr:street");
        var num = tagStr(tags, "addr:housenumber");
        var city = tagStr(tags, "addr:city");
        var s = "";
        if (street.length() > 0) {
            s = street;
            if (num.length() > 0) { s += " " + num; }
        }
        if (city.length() > 0) {
            if (s.length() > 0) { s += ", "; }
            s += city;
        }
        return s;
    }

    private function airportLine(ap) as String {
        if (!(ap instanceof Dictionary)) { return ""; }
        var city = tagStr(ap, "municipality");
        var iata = tagStr(ap, "iata_code");
        var name = tagStr(ap, "name");
        var s = (city.length() > 0) ? city : name;
        if (iata.length() > 0) {
            s = (s.length() > 0) ? (s + " (" + iata + ")") : iata;
        }
        return s;
    }

    // Greedy word-wrap to maxW pixels.
    private function wrapText(dc as Dc, text as String, font as Graphics.FontType,
                              maxW as Number) as Array<String> {
        var out = [] as Array<String>;
        if (text.length() == 0) {
            out.add("");
            return out;
        }
        var words = splitSpaces(text);
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            var word = words[i];
            var trial = (line.length() == 0) ? word : (line + " " + word);
            if (dc.getTextWidthInPixels(trial, font) <= maxW) {
                line = trial;
            } else {
                if (line.length() > 0) { out.add(line); }
                line = word;
            }
        }
        if (line.length() > 0) { out.add(line); }
        if (out.size() == 0) { out.add(""); }
        return out;
    }

    private function splitSpaces(s as String) as Array<String> {
        var out = [] as Array<String>;
        var chars = s.toCharArray();
        var cur = "";
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ') {
                if (cur.length() > 0) { out.add(cur); cur = ""; }
            } else {
                cur += chars[i].toString();
            }
        }
        if (cur.length() > 0) { out.add(cur); }
        return out;
    }
}

class DetailDelegate extends WatchUi.BehaviorDelegate {

    private var _view as DetailView;

    function initialize(view as DetailView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP) { _view.scrollBy(80); return true; }
        if (d == WatchUi.SWIPE_DOWN) { _view.scrollBy(-80); return true; }
        return false;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (k == WatchUi.KEY_DOWN) { _view.scrollBy(80); return true; }
        if (k == WatchUi.KEY_UP) { _view.scrollBy(-80); return true; }
        return false;
    }

    function onNextPage() as Boolean {
        _view.scrollBy(160);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.scrollBy(-160);
        return true;
    }

    function onSelect() as Boolean {
        _view.toggleTarget();
        return true;
    }
}
