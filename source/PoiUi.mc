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
        WatchUi.pushView(menu, new FilterMenuDelegate(model), WatchUi.SLIDE_UP);
    }

    function pushPoiList(model as PoiModel) as Void {
        var vis = model.visible;
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.MenuNearby)
        });
        if (model.targetPoi != null) {
            menu.addItem(new WatchUi.MenuItem(
                WatchUi.loadResource(Rez.Strings.ClearTarget) as String,
                null, -2, null));
        }
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
                _model.targetPoi = null;
            } else if (id >= 0 && id < _items.size()) {
                _model.targetPoi = _items[id];
            }
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
