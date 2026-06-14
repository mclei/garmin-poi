import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Menus: category filters and the nearest-POI list.
module PoiUi {

    function pushFilterMenu(model as PoiModel) as Void {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.MenuFilters)
        });
        for (var c = 0; c < NUM_CATS; c++) {
            menu.addItem(new WatchUi.ToggleMenuItem(
                WatchUi.loadResource(PoiCat.label(c)) as String,
                null, c, model.catEnabled[c], null));
        }
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.MenuRefresh) as String,
            null, "refresh", null));
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.MenuCalibrate) as String,
            null, "calibrate", null));
        WatchUi.pushView(menu, new FilterMenuDelegate(model), WatchUi.SLIDE_UP);
    }

    function pushPoiList(model as PoiModel) as Void {
        var showAll = model.listShowAll;
        var vis = showAll ? model.poisAllDirections() : model.visible;
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.MenuNearby)
        });
        // First item names the CURRENT field-of-view mode (so you can see which
        // is active); tapping it switches to the other and rebuilds the list.
        var curMode = showAll ? Rez.Strings.ListAll : Rez.Strings.ListInView;
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(curMode) as String,
            WatchUi.loadResource(Rez.Strings.ListTapSwitch) as String,
            -2, null));
        if (vis.size() == 0) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.NoPois) as String,
                null, -1, null));
        }
        var n = vis.size();
        if (n > 30) { n = 30; }
        for (var i = 0; i < n; i++) {
            var p = vis[i];
            var sub = GeoUtils.formatDistance(p.distance)
                    + " " + GeoUtils.cardinal(p.bearing)
                    + " | " + PoiCat.shortName(p.category);
            menu.addItem(new WatchUi.MenuItem(p.name, sub, i, null));
        }
        WatchUi.pushView(menu, new PoiListDelegate(model, vis), WatchUi.SLIDE_LEFT);
    }

    // Scrollable detail page for a single POI / aircraft.
    function pushDetail(model as PoiModel, poi as Poi) as Void {
        var v = new DetailView(model, poi);
        WatchUi.pushView(v, new DetailDelegate(v), WatchUi.SLIDE_LEFT);
    }

    // Quick one-shot picker: load only one category now, without touching the
    // saved filters (they apply again on the next normal search).
    function pushQuickMenu(model as PoiModel) as Void {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.MenuShowOnly)
        });
        for (var c = 0; c < NUM_CATS; c++) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(PoiCat.label(c)) as String, null, c, null));
        }
        if (model.oneShotCategory() >= 0) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.MenuMyFilters) as String,
                null, -1, null));
        }
        WatchUi.pushView(menu, new QuickMenuDelegate(model), WatchUi.SLIDE_UP);
    }
}

class QuickMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as PoiModel;

    function initialize(model as PoiModel) {
        Menu2InputDelegate.initialize();
        _model = model;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) {
            if (id == -1) {
                _model.clearOneShot();
            } else {
                _model.loadOnlyCategory(id);
            }
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class FilterMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as PoiModel;

    function initialize(model as PoiModel) {
        Menu2InputDelegate.initialize();
        _model = model;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof String && id.equals("refresh")) {
            _model.forceRefresh();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        if (id instanceof String && id.equals("calibrate")) {
            WatchUi.pushView(new CalibrationView(_model),
                             new CalibrationDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        if (item instanceof WatchUi.ToggleMenuItem && id instanceof Number) {
            _model.setCategory(id, item.isEnabled());
        }
    }
}

class PoiListDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as PoiModel;
    private var _items as Array<Poi>;

    function initialize(model as PoiModel, items as Array<Poi>) {
        Menu2InputDelegate.initialize();
        _model = model;
        _items = items;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) {
            if (id == -2) {
                // toggle the field-of-view filter and rebuild the list
                _model.listShowAll = !_model.listShowAll;
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
                PoiUi.pushPoiList(_model);
            } else if (id >= 0 && id < _items.size()) {
                PoiUi.pushDetail(_model, _items[id]); // list item -> detail page
            }
        }
    }
}
