import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Scrollable detail page for one POI: name, type, distance/bearing and the
// address (all carried from the Photon result, no extra fetch), word-wrapped.
class DetailView extends WatchUi.View {

    private var _model as PoiModel;
    private var _poi as Poi;
    private var _scroll as Number;
    private var _maxScroll as Number;

    function initialize(model as PoiModel, poi as Poi) {
        View.initialize();
        _model = model;
        _poi = poi;
        _scroll = 0;
        _maxScroll = 0;
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
        // On round screens the corners are cut off, so centre the text with a
        // wider margin and extra top/bottom padding; rectangular screens keep
        // the left-aligned layout that uses the full width.
        var round = (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND);
        var margin = round ? (w * 0.18).toNumber() : (w * 0.08).toNumber();
        var maxW = w - 2 * margin;
        var pad = round ? (h * 0.16).toNumber() : 8;
        var tx = round ? (w / 2) : margin;
        var just = round ? Graphics.TEXT_JUSTIFY_CENTER : Graphics.TEXT_JUSTIFY_LEFT;

        var blocks = buildBlocks();

        // Measure total height first so we can clamp scrolling.
        var total = pad;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            var fh = dc.getFontHeight(b[1]);
            var lines = wrapText(dc, b[0], b[1], maxW);
            total += lines.size() * fh + 2;
        }
        total += pad;
        _maxScroll = total - h;
        if (_maxScroll < 0) { _maxScroll = 0; }
        if (_scroll > _maxScroll) { _scroll = _maxScroll; }

        // Draw.
        var y = pad - _scroll;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            var font = b[1];
            var fh = dc.getFontHeight(font);
            var lines = wrapText(dc, b[0], font, maxW);
            for (var j = 0; j < lines.size(); j++) {
                if (y + fh > 0 && y < h) {
                    dc.setColor(b[2], Graphics.COLOR_TRANSPARENT);
                    dc.drawText(tx, y, font, lines[j], just);
                }
                y += fh + 2;
            }
        }

        drawScrollbar(dc, w, h, total, round);
        drawLockBadge(dc, w, round);
    }

    // Always-visible badge showing whether this POI is the locked target.
    private function drawLockBadge(dc as Dc, w as Number, round as Boolean) as Void {
        var locked = (_model.targetPoi == _poi);
        var txt = locked ? "LOCKED" : "UNLOCKED";
        var font = Graphics.FONT_XTINY;
        var tw = dc.getTextWidthInPixels(txt, font);
        var fh = dc.getFontHeight(font);
        var bw = tw + 12;
        var bh = fh + 4;
        // Round: centre at the top (corners are clipped). Rectangular: top-right
        // (leaving room for the scrollbar at w - 4).
        var bx = round ? ((w - bw) / 2) : (w - bw - 8);
        var by = round ? 18 : 4;
        // Mask the content underneath so the badge stays legible.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(bx - 2, by - 2, bw + 4, bh + 4);
        if (locked) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, bw, bh, 4);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(bx, by, bw, bh, 4);
        }
        dc.drawText(bx + 6, by + 2, font, txt, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawScrollbar(dc as Dc, w as Number, h as Number,
                                   total as Number, round as Boolean) as Void {
        if (_maxScroll <= 0) { return; }
        var barH = (h * h) / total;
        if (barH < 16) { barH = 16; }
        var trackH = h - barH;
        var pos = (trackH * _scroll) / _maxScroll;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        // inset from the edge on round so the bar isn't clipped at the curve
        dc.fillRectangle(w - (round ? 9 : 4), pos, 3, barH);
    }

    // Build display blocks: each is [text, font, color].
    private function buildBlocks() as Array {
        var b = [] as Array;
        buildPoiBlocks(b);
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

        if (_poi.addr.length() > 0) {
            b.add(["Address: " + _poi.addr,
                   Graphics.FONT_XTINY, Graphics.COLOR_WHITE]);
            b.add(["", Graphics.FONT_XTINY, Graphics.COLOR_BLACK]);
        }
        b.add([_poi.lat.format("%.5f") + ", " + _poi.lon.format("%.5f"),
               Graphics.FONT_XTINY, Graphics.COLOR_DK_GRAY]);
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
