import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// About screen: icon, full store name, version (+ build ID), author, contact and
// the data credits. Everything is centred and the block is centred vertically, so
// it suits round screens; on small screens the icon is left out and a long name
// is split after the colon.
class AboutView extends WatchUi.View {
    private var _icon as WatchUi.BitmapResource? = null;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        _icon = WatchUi.loadResource(Rez.Drawables.LauncherIcon) as WatchUi.BitmapResource;
    }

    function onHide() as Void {
        _icon = null;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // [text, font, colour, gap after]
        var rows = [] as Array<Array>;
        var name = Build.FULL_NAME;
        var big = Graphics.FONT_SMALL;
        var small = Graphics.FONT_XTINY;
        var colon = name.find(": ");
        if (dc.getTextWidthInPixels(name, big) > w * 0.8 && colon != null) {
            rows.add([name.substring(0, colon + 1), big, Graphics.COLOR_WHITE, 0]);
            rows.add([name.substring(colon + 2, name.length()), big, Graphics.COLOR_WHITE, 4]);
        } else {
            rows.add([name, big, Graphics.COLOR_WHITE, 4]);
        }
        rows.add([(WatchUi.loadResource(Rez.Strings.AboutVersion) as String) + " " + Build.VERSION + " (" + Build.ID + ")",
                  small, Graphics.COLOR_LT_GRAY, 8]);
        rows.add([Build.AUTHOR, small, Graphics.COLOR_WHITE, 0]);
        rows.add([Build.CONTACT, small, Graphics.COLOR_WHITE, 8]);
        rows.add([WatchUi.loadResource(Rez.Strings.AboutCredit1) as String, small, Graphics.COLOR_LT_GRAY, 0]);
        rows.add([WatchUi.loadResource(Rez.Strings.AboutCredit2) as String, small, Graphics.COLOR_LT_GRAY, 0]);

        var total = 0;
        for (var i = 0; i < rows.size(); i++) {
            total += dc.getFontHeight(rows[i][1]) + rows[i][3];
        }
        var icon = _icon;
        if (icon != null && total + icon.getHeight() + 6 <= h * 0.86) {
            total += icon.getHeight() + 6;
        } else {
            icon = null;
        }
        var y = (h - total) / 2;
        if (icon != null) {
            dc.drawBitmap(cx - icon.getWidth() / 2, y, icon);
            y += icon.getHeight() + 6;
        }
        for (var i = 0; i < rows.size(); i++) {
            dc.setColor(rows[i][2], Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, rows[i][1], rows[i][0], Graphics.TEXT_JUSTIFY_CENTER);
            y += dc.getFontHeight(rows[i][1]) + rows[i][3];
        }
    }
}
