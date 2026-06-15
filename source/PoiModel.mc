import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.WatchUi;

// Global Overpass mirrors (all carry worldwide data), tried in order with
// failover. The main overpass-api.de instance round-robins ~50% of requests to
// a backend that returns HTTP 406 (-> -400 on the watch), so it is NOT reliable
// enough to lead with; the mail.ru mirror answered 100% in testing. Reorder
// this list to prefer a different instance (e.g. a self-hosted one).
const OVERPASS_MIRRORS = [
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass-api.de/api/interpreter"
] as Array<String>;

// Land POIs use an expanding search: start tight and widen only when nothing
// is found, up to 5 km. The starting radius depends on GPS precision (50 m on
// a good fix, wider when approximate) - see startLadderIndex(). In a dense
// city you stop almost immediately (tiny response); in open country you reach
// far, where there is little to return anyway.
const POI_RADII = [50, 100, 200, 500, 1000, 2000, 5000] as Array<Number>;

// Hard cap on returned elements, so a dense stopping radius can't produce a
// response too large to parse. The query uses Overpass `convert` to project
// only the fields we use (~230 bytes/element), so 60 elements is ~14 KB. We
// only display the nearest maxPois anyway. No "qt" sort: quadtile order biases
// the capped set to one corner; plain id order is even and we distance-sort.
const POI_MAX_ELEMENTS = 60;

// Keep widening the search until at least this many POIs are found (or the
// widest radius is reached) - a tight radius returning only a couple of hits
// isn't useful, so gather more from a wider circle.
const POI_MIN_RESULTS = 10;

// Field of view for land POIs: only those whose bearing is within FOV_ENTER of
// the current heading are shown ("what you're looking at", ~90 deg total). Once
// shown, a POI stays until it passes FOV_EXIT - the hysteresis stops it from
// flickering on/off as you turn near the edge.
const FOV_ENTER = 45.0;
const FOV_EXIT = 55.0;

// Range used to scale the radar dots (matches the widest expanding radius).
const POI_RANGE = 5000.0;

// Compass smoothing: ignore heading jitter smaller than the deadband, and ease
// toward larger (real) changes so the display doesn't twitch with magnetometer
// noise.
const HEADING_DEADBAND = 2.0;  // degrees
const HEADING_SMOOTH = 0.5;    // 0..1 fraction moved toward a new reading

// Keep-display-awake heuristic: hold the screen on while the watch is roughly
// face-up AND being moved a little (i.e. held/looked at, not flat-still on a
// desk). KEEPAWAKE_MOVE is the milliG L1 change counted as movement;
// KEEPAWAKE_HOLD is how many seconds to keep awake after the last movement.
const KEEPAWAKE_MOVE = 40;
const KEEPAWAKE_HOLD = 3;

// Central application state: position, heading, POI data and fetch logic.
class PoiModel {

    // Position / heading
    public var lat as Double?;
    public var lon as Double?;
    public var gpsQuality as Number;
    public var posApprox as Boolean;  // true until a usable-quality fix arrives
    public var headingDeg as Float;
    private var _haveHeading as Boolean;
    // keep-awake: last accel sample + when motion/backlight were last seen
    private var _ax as Number;
    private var _ay as Number;
    private var _az as Number;
    private var _haveAccel as Boolean;
    private var _lastMoveSec as Number;
    private var _lastLightSec as Number;

    // Data
    public var pois as Array<Poi>;       // land POIs, distance-sorted
    public var visible as Array<Poi>;    // field-of-view filtered, distance-sorted
    public var targetPoi as Poi?;        // user-locked target
    public var listShowAll as Boolean;   // Nearby list: all directions vs in-view only

    // Status
    public var poiStatus as Number;
    public var poiError as Number;

    // Settings
    public var maxPois as Number;
    public var catEnabled as Array<Boolean>;

    private var _fetchPending as Boolean;
    private var _needPoiFetch as Boolean;
    private var _lastPoiAttemptSec as Number;
    private var _fetchLat as Double?;
    private var _fetchLon as Double?;
    private var _fetchedMask as Number;  // land categories included in last fetch
    private var _ladderIdx as Number;    // current step in POI_RADII expanding search
    private var _opIndex as Number;      // current Overpass mirror
    private var _opTries as Number;      // consecutive failures on this mirror
    private var _oneShotCat as Number;   // temporary "show only this" category, -1 = off
    private var _oneShotPending as Boolean;
    private var _dirty as Boolean;

    // Full-tag cache for the POI detail page (key "type/id" -> tags dict;
    // "" cached on failure). Fetched on demand when a detail page opens.
    private var _poiDetail as Dictionary;
    private var _detailPending as Boolean;
    private var _detailKey as String?;
    private var _lastDetailSec as Number;

    function initialize() {
        lat = null;
        lon = null;
        gpsQuality = 0;
        posApprox = false;
        headingDeg = 0.0;
        _haveHeading = false;
        _ax = 0;
        _ay = 0;
        _az = 0;
        _haveAccel = false;
        _lastMoveSec = 0;
        _lastLightSec = 0;
        pois = [] as Array<Poi>;
        visible = [] as Array<Poi>;
        targetPoi = null;
        listShowAll = false;
        poiStatus = STATUS_IDLE;
        poiError = 0;
        maxPois = 40;
        catEnabled = new Array<Boolean>[NUM_CATS];
        for (var c = 0; c < NUM_CATS; c++) {
            catEnabled[c] = PoiCat.defaultEnabled(c);
        }
        _fetchPending = false;
        _needPoiFetch = false;
        _lastPoiAttemptSec = 0;
        _fetchLat = null;
        _fetchLon = null;
        _fetchedMask = 0;
        _ladderIdx = 0;
        _opIndex = 0;
        _opTries = 0;
        _oneShotCat = -1;
        _oneShotPending = false;
        _dirty = true;
        _poiDetail = {} as Dictionary;
        _detailPending = false;
        _detailKey = null;
        _lastDetailSec = 0;
        reloadSettings();
    }

    function start() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS,
                                      method(:onPosition));
        // Seed with the cached last-known location so POIs can load while the
        // GPS is still acquiring a precise fix. Marked approximate until a
        // usable-quality fix arrives (handled in onPosition).
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            lat = deg[0].toDouble();
            lon = deg[1].toDouble();
            var q = (info.accuracy != null) ? info.accuracy as Number : 0;
            gpsQuality = q;
            posApprox = (q < Position.QUALITY_USABLE);
            updateDerived();
        }
    }

    function stop() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE,
                                      method(:onPosition));
    }

    // ---- settings ----

    function reloadSettings() as Void {
        maxPois = getNumProp("maxPois", 40);
        if (maxPois < 10) { maxPois = 10; }
        if (maxPois > 100) { maxPois = 100; }
        var arr = new Array<Boolean>[NUM_CATS];
        for (var c = 0; c < NUM_CATS; c++) {
            arr[c] = getBoolProp(PoiCat.propKey(c), PoiCat.defaultEnabled(c));
        }
        catEnabled = arr;
        // refetch if an enabled land category was not part of the last fetch
        for (var c = 0; c < NUM_LAND_CATS; c++) {
            if (catEnabled[c] && (_fetchedMask & (1 << c)) == 0) {
                _needPoiFetch = true;
            }
        }
        _dirty = true;
    }

    function setCategory(cat as Number, enabled as Boolean) as Void {
        catEnabled[cat] = enabled;
        try {
            Application.Properties.setValue(PoiCat.propKey(cat), enabled);
        } catch (e) {
        }
        if (enabled && cat < NUM_LAND_CATS && (_fetchedMask & (1 << cat)) == 0) {
            _needPoiFetch = true;
        }
        _dirty = true;
    }

    function forceRefresh() as Void {
        _needPoiFetch = true;
        _lastPoiAttemptSec = 0;
    }

    // Whether a category is active for the current search/display: while a
    // one-shot override is set, only that category counts; otherwise the saved
    // toggles apply. Saved settings are never modified by the override.
    function effectiveCatEnabled(cat as Number) as Boolean {
        if (_oneShotCat >= 0) { return cat == _oneShotCat; }
        return catEnabled[cat];
    }

    function oneShotCategory() as Number {
        return _oneShotCat;
    }

    // One-time shot: show only this category now (even one disabled in the
    // saved filters), without changing settings. The next normal search
    // (move >400 m / refresh / filter change) reverts to the saved filters.
    function loadOnlyCategory(cat as Number) as Void {
        _oneShotCat = cat;
        _dirty = true;
        // Reset the fresh-search triggers so the override can't be cleared on
        // the very next tick before it has loaded.
        _needPoiFetch = false;
        if (lat != null) { _fetchLat = lat; _fetchLon = lon; }
        _lastPoiAttemptSec = Time.now().value();
        pois = [] as Array<Poi>;    // drop stale data of other categories
        _oneShotPending = true;     // trigger a fetch for just this category
    }

    function clearOneShot() as Void {
        if (_oneShotCat < 0) { return; }
        _oneShotCat = -1;
        forceRefresh();                 // back to the saved filters
    }

    private function getNumProp(key as String, def as Number) as Number {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        return (v instanceof Number) ? v : def;
    }

    private function getBoolProp(key as String, def as Boolean) as Boolean {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        return (v instanceof Boolean) ? v : def;
    }

    // ---- position & heading ----

    function onPosition(info as Position.Info) as Void {
        if (info.position != null) {
            var deg = info.position.toDegrees();
            lat = deg[0].toDouble();
            lon = deg[1].toDouble();
            var q = (info.accuracy != null) ? info.accuracy as Number : gpsQuality;
            gpsQuality = q;
            // First usable-quality fix: drop the approximate flag and refine the
            // POI list at the precise location even if we moved less than 400 m.
            if (posApprox && q >= Position.QUALITY_USABLE) {
                posApprox = false;
                _needPoiFetch = true;
                _lastPoiAttemptSec = 0;
            }
            updateDerived();
        }
    }

    // Called ~5x/s from the main view timer
    function tick() as Void {
        var now = Time.now().value();
        var si = Sensor.getInfo();
        if (si != null && si.heading != null) {
            var raw = GeoUtils.normDeg(Math.toDegrees(si.heading).toFloat());
            if (!_haveHeading) {
                headingDeg = raw;          // first reading: take it as-is
                _haveHeading = true;
            } else {
                var diff = GeoUtils.angleDiff(raw, headingDeg);
                if (diff > HEADING_DEADBAND || diff < -HEADING_DEADBAND) {
                    headingDeg = GeoUtils.normDeg(headingDeg + diff * HEADING_SMOOTH);
                }
            }
        }
        updateKeepAwake(si, now);
        if (lat == null) { return; }
        maybeFetchPois(now);
        // Rebuilt every tick so the field-of-view filter tracks the heading as
        // you turn (re-filters the already-loaded POIs, no refetch).
        rebuildVisible();
    }

    // Hold the display on while the watch is roughly face-up and being moved a
    // little (held/looked at), so it doesn't sleep mid-use; when it's level but
    // perfectly still (lying on a desk) it's allowed to sleep normally.
    private function updateKeepAwake(si as Sensor.Info?, now as Number) as Void {
        if (si == null) { return; }
        var a = si.accel;
        if (!(a instanceof Array) || a.size() < 3) { return; }
        var x = a[0];
        var y = a[1];
        var z = a[2];
        if (_haveAccel) {
            var dx = x - _ax; if (dx < 0) { dx = -dx; }
            var dy = y - _ay; if (dy < 0) { dy = -dy; }
            var dz = z - _az; if (dz < 0) { dz = -dz; }
            if (dx + dy + dz > KEEPAWAKE_MOVE) { _lastMoveSec = now; }
        }
        _ax = x; _ay = y; _az = z; _haveAccel = true;

        // "Level/face-up": the up axis dominates, i.e. within ~60 deg of flat
        // (4*z^2 > x^2+y^2+z^2  <=>  z/|a| > 0.5), and z positive (face up).
        var magSq = x * x + y * y + z * z;
        var level = (z > 0) && (z * z * 4 > magSq);
        var active = level && ((now - _lastMoveSec) <= KEEPAWAKE_HOLD);

        // Re-arm the backlight ~once a second while active. Guard + try/catch:
        // on AMOLED, burn-in protection throws if held on too long - ignore it.
        if (active && (now - _lastLightSec) >= 1) {
            _lastLightSec = now;
            if (Attention has :backlight) {
                try {
                    Attention.backlight(true);
                } catch (e) {
                }
            }
        }
    }

    // ---- visible set / focus ----

    private function updateDerived() as Void {
        if (lat == null) { return; }
        var la = lat as Double;
        var lo = lon as Double;
        for (var i = 0; i < pois.size(); i++) {
            var p = pois[i];
            p.distance = GeoUtils.distanceM(la, lo, p.lat, p.lon);
            p.bearing = GeoUtils.bearingDeg(la, lo, p.lat, p.lon);
        }
        var t = targetPoi;
        if (t != null) {
            t.distance = GeoUtils.distanceM(la, lo, t.lat, t.lon);
            t.bearing = GeoUtils.bearingDeg(la, lo, t.lat, t.lon);
        }
        _dirty = true;
    }

    private function rebuildVisible() as Void {
        var out = [] as Array<Poi>;
        var hdg = headingDeg;
        // Land POIs: keep only those in the field of view ahead, with
        // hysteresis (enter at FOV_ENTER, leave at FOV_EXIT) so they don't
        // flicker as you turn. Recomputed every tick as the heading changes.
        for (var i = 0; i < pois.size(); i++) {
            var p = pois[i];
            if (!effectiveCatEnabled(p.category)) {
                p.inView = false;
                continue;
            }
            var d = GeoUtils.angleDiff(p.bearing, hdg);
            if (d < 0) { d = -d; }
            var limit = p.inView ? FOV_EXIT : FOV_ENTER;
            p.inView = (d <= limit);
            if (p.inView) { out.add(p); }
        }
        GeoUtils.sortByDistance(out);
        visible = out;
        var t = targetPoi;
        if (t != null && !effectiveCatEnabled(t.category)) {
            targetPoi = null;
        }
        _dirty = false;
    }

    // All category-enabled POIs, distance-sorted, ignoring the field-of-view
    // filter - used by the Nearby list when "all directions" is selected.
    function poisAllDirections() as Array<Poi> {
        var out = [] as Array<Poi>;
        for (var i = 0; i < pois.size(); i++) {
            var p = pois[i];
            if (effectiveCatEnabled(p.category)) { out.add(p); }
        }
        GeoUtils.sortByDistance(out);
        return out;
    }

    // The POI to feature on screen: locked target, else nearest within the
    // +-35 deg cone in front of the user, else nearest overall.
    function focusedPoi() as Poi? {
        if (targetPoi != null) { return targetPoi; }
        var best = null;
        var bestDist = 99999999.0;
        for (var i = 0; i < visible.size(); i++) {
            var p = visible[i];
            var d = GeoUtils.angleDiff(p.bearing, headingDeg);
            if (d < 0) { d = -d; }
            if (d <= 35.0 && p.distance < bestDist) {
                best = p;
                bestDist = p.distance;
            }
        }
        if (best == null && visible.size() > 0) {
            best = visible[0];
        }
        return best;
    }

    private function anyLandCatEnabled() as Boolean {
        for (var c = 0; c < NUM_LAND_CATS; c++) {
            if (effectiveCatEnabled(c)) { return true; }
        }
        return false;
    }

    // ---- Overpass (OpenStreetMap POIs) ----

    private function maybeFetchPois(now as Number) as Void {
        if (_fetchPending) { return; }
        // One-shot land search just requested: fetch it without clearing the
        // override (so following normal searches can revert it).
        if (_oneShotPending && _oneShotCat >= 0 && _oneShotCat < NUM_LAND_CATS) {
            _oneShotPending = false;
            _ladderIdx = startLadderIndex();
            fetchPois();
            return;
        }
        // Decide whether a fresh normal search is warranted (first fix, a
        // filter/refresh request, or moving far). Computed before the land
        // check so an aircraft-only one-shot still reverts on these triggers.
        var since = now - _lastPoiAttemptSec;
        var fresh = false;
        if (_fetchLat == null) {
            fresh = (since >= 5);
        } else if (_needPoiFetch && since >= 10) {
            fresh = true;
        } else if (since >= 60) {
            var moved = GeoUtils.distanceM(lat as Double, lon as Double,
                                           _fetchLat as Double, _fetchLon as Double);
            fresh = (moved > 400.0);
        }
        if (fresh && _oneShotCat >= 0) {
            _oneShotCat = -1;   // a normal search reverts the one-time override
            _dirty = true;
        }
        if (!anyLandCatEnabled()) { return; }
        // Retry after a transient failure. Short delay because overpass-api.de's
        // 406s alternate per request, so a quick retry usually succeeds.
        if (poiStatus == STATUS_ERROR && since >= 3) {
            fetchPois();
            return;
        }
        if (fresh) {
            _ladderIdx = startLadderIndex();
            fetchPois();
        }
    }

    // Tightest sensible starting radius for the expanding search, based on how
    // precise the current fix is: a 50 m search only makes sense when the
    // position is accurate to a few metres; an approximate/last-known position
    // starts wider so it isn't searching the wrong 50 m circle.
    private function startLadderIndex() as Number {
        if (!posApprox && gpsQuality >= Position.QUALITY_GOOD)   { return 0; } // 50 m
        if (!posApprox && gpsQuality >= Position.QUALITY_USABLE) { return 2; } // 200 m
        return 3; // approximate or poor -> 500 m
    }

    private function fetchPois() as Void {
        _fetchPending = true;
        poiStatus = STATUS_LOADING;
        _lastPoiAttemptSec = Time.now().value();
        _fetchLat = lat;
        _fetchLon = lon;
        _needPoiFetch = false;
        var mask = 0;
        for (var c = 0; c < NUM_LAND_CATS; c++) {
            if (effectiveCatEnabled(c)) { mask |= (1 << c); }
        }
        // A broad nwr[historic] query also returns castles/ruins, so mark them
        // covered to avoid a redundant refetch when those toggles flip on.
        if ((mask & (1 << CAT_MONUMENT)) != 0) {
            mask |= (1 << CAT_CASTLE) | (1 << CAT_RUINS);
        }
        _fetchedMask = mask;
        Communications.makeWebRequest(OVERPASS_MIRRORS[_opIndex],
                                      {"data" => buildQuery(POI_RADII[_ladderIdx])},
                                      overpassOptions(), method(:onPoiResponse));
    }

    private function overpassOptions() as Dictionary {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // JSON output (application/json is the only text-ish type the watch accepts
    // - CSV is text/csv which gives -400). Overpass `convert` projects only the
    // fields we use (~230 bytes/element vs ~450 for full tags), keeping the
    // response small enough to parse; center(geom()) gives way/relation centers.
    private function buildQuery(radius as Number) as String {
        var la = (lat as Double).format("%.5f");
        var lo = (lon as Double).format("%.5f");
        var ar = "(around:" + radius.toString() + "," + la + "," + lo + ");";
        var q = "[out:json][timeout:25];(";
        // Historic: a broad nwr[historic] covers monuments/memorials and is
        // classified down to castles/ruins; if only the narrow toggles are on,
        // fetch just those subsets.
        if (effectiveCatEnabled(CAT_MONUMENT)) {
            q += "nwr[historic]" + ar;
        } else {
            if (effectiveCatEnabled(CAT_CASTLE)) {
                q += "nwr[historic~\"^(castle|fort|fortress|city_gate|citadel|castle_wall|manor|palace)$\"]" + ar;
            }
            if (effectiveCatEnabled(CAT_RUINS)) {
                q += "nwr[historic~\"^(ruins|archaeological_site)$\"]" + ar;
            }
        }
        if (effectiveCatEnabled(CAT_VIEWPOINT)) {
            q += "nwr[tourism~\"^(attraction|viewpoint)$\"]" + ar;
        }
        var food = "";
        if (effectiveCatEnabled(CAT_RESTAURANT)) { food += "restaurant|"; }
        if (effectiveCatEnabled(CAT_CAFE)) { food += "cafe|fast_food|ice_cream|"; }
        if (effectiveCatEnabled(CAT_BAR)) { food += "bar|pub|biergarten|"; }
        if (food.length() > 0) {
            food = food.substring(0, food.length() - 1); // drop trailing '|'
            q += "nwr[amenity~\"^(" + food + ")$\"]" + ar;
        }
        if (effectiveCatEnabled(CAT_MUSEUM)) {
            q += "nwr[tourism~\"^(museum|gallery|artwork)$\"]" + ar;
        }
        if (effectiveCatEnabled(CAT_THEATRE)) {
            q += "nwr[amenity~\"^(theatre|cinema|arts_centre)$\"]" + ar;
        }
        if (effectiveCatEnabled(CAT_WORSHIP)) {
            q += "nwr[amenity=place_of_worship]" + ar;
        }
        q += ")->.r;.r convert poi ::id=id(),tp=type(),::geom=center(geom()),"
           + "name=t[\"name\"],h=t[\"historic\"],to=t[\"tourism\"],a=t[\"amenity\"];"
           + "out geom " + POI_MAX_ELEMENTS.toString() + ";";
        return q;
    }

    function onPoiResponse(code as Number, data as Dictionary or String or Null) as Void {
        _fetchPending = false;
        if (code == 200 && data instanceof Dictionary) {
            _opTries = 0;
            var fresh = parseElements(data["elements"]);
            // Show what this radius found right away, then keep widening in the
            // background if there are still too few. Each wider circle is a
            // superset, so the on-screen list just grows as the steps return -
            // the nearest points appear immediately, no waiting for 10.
            finalizePois(fresh);
            if (fresh.size() < POI_MIN_RESULTS && _ladderIdx < POI_RADII.size() - 1) {
                _ladderIdx++;
                fetchPois();
            }
        } else {
            // Failure (overpass-api.de intermittently 406s/504s -> -400). Its
            // failures alternate per request, so retry the SAME mirror a few
            // times (fast) before rotating to another - that avoids stalling on
            // a mirror that may be slow/unreachable from the watch.
            poiStatus = STATUS_ERROR;
            poiError = code;
            _opTries++;
            if (_opTries >= 3) {
                _opIndex = (_opIndex + 1) % OVERPASS_MIRRORS.size();
                _opTries = 0;
            }
        }
        WatchUi.requestUpdate();
    }

    private function finalizePois(fresh as Array<Poi>) as Void {
        if (lat != null) {
            var la = lat as Double;
            var lo = lon as Double;
            for (var i = 0; i < fresh.size(); i++) {
                var p = fresh[i];
                p.distance = GeoUtils.distanceM(la, lo, p.lat, p.lon);
                p.bearing = GeoUtils.bearingDeg(la, lo, p.lat, p.lon);
            }
        }
        GeoUtils.sortByDistance(fresh);
        pois = dedupeAndCap(fresh);
        _dirty = true;
        poiStatus = STATUS_IDLE;
        poiError = 0;
    }

    // Parse the projected `convert` output. Each element is:
    //   {type:"poi", id:<origId>, geometry:{coordinates:[lon,lat]},
    //    tags:{tp:<node|way|relation>, name, h, to, a}}
    private function parseElements(elements) as Array<Poi> {
        var out = [] as Array<Poi>;
        if (!(elements instanceof Array)) { return out; }
        for (var i = 0; i < elements.size(); i++) {
            var el = elements[i];
            if (!(el instanceof Dictionary)) { continue; }
            var tags = el["tags"];
            if (!(tags instanceof Dictionary)) { continue; }
            var geom = el["geometry"];
            if (!(geom instanceof Dictionary)) { continue; }
            var coords = geom["coordinates"];
            if (!(coords instanceof Array) || coords.size() < 2) { continue; }
            var plon = numToD(coords[0]);   // GeoJSON order is [lon, lat]
            var plat = numToD(coords[1]);
            if (plat == null || plon == null) { continue; }
            var cd = categorizeTags(strOf(tags["h"]),
                                    strOf(tags["to"]),
                                    strOf(tags["a"]));
            if (cd == null) { continue; }
            var subtype = prettify(cd[1] as String);
            var name = strOf(tags["name"]);
            if (name.length() == 0) { name = subtype; }
            var p = new Poi(name, plat, plon, cd[0] as Number, subtype);
            p.osmType = strOf(tags["tp"]);
            var idv = el["id"];
            p.osmId = (idv != null) ? idv.toString() : "";
            out.add(p);
        }
        return out;
    }

    private function strOf(v) as String {
        return (v instanceof String) ? v : "";
    }

    // Classify from the historic/tourism/amenity column values (empty = absent).
    private function categorizeTags(h as String, t as String, a as String) as Array? {
        if (h.length() > 0) {
            if (h.equals("castle") || h.equals("fort") || h.equals("fortress")
                || h.equals("city_gate") || h.equals("citadel")
                || h.equals("castle_wall") || h.equals("manor")
                || h.equals("palace")) {
                return [CAT_CASTLE, h];
            }
            if (h.equals("ruins") || h.equals("archaeological_site")) {
                return [CAT_RUINS, h];
            }
            return [CAT_MONUMENT, h]; // monuments, memorials, other historic
        }
        if (t.length() > 0) {
            if (t.equals("attraction") || t.equals("viewpoint")) {
                return [CAT_VIEWPOINT, t];
            }
            if (t.equals("museum") || t.equals("gallery") || t.equals("artwork")) {
                return [CAT_MUSEUM, t];
            }
        }
        if (a.length() > 0) {
            if (a.equals("restaurant")) { return [CAT_RESTAURANT, a]; }
            if (a.equals("cafe") || a.equals("fast_food")
                || a.equals("ice_cream")) {
                return [CAT_CAFE, a];
            }
            if (a.equals("bar") || a.equals("pub") || a.equals("biergarten")) {
                return [CAT_BAR, a];
            }
            if (a.equals("theatre") || a.equals("cinema")
                || a.equals("arts_centre")) {
                return [CAT_THEATRE, a];
            }
            if (a.equals("place_of_worship")) { return [CAT_WORSHIP, a]; }
        }
        return null;
    }

    // Keep the nearest entry per (name, category); cap at maxPois.
    private function dedupeAndCap(arr as Array<Poi>) as Array<Poi> {
        var seen = {} as Dictionary<String, Boolean>;
        var out = [] as Array<Poi>;
        for (var i = 0; i < arr.size(); i++) {
            var p = arr[i];
            var key = p.name + "|" + p.category.toString();
            if (seen[key] == null) {
                seen[key] = true;
                out.add(p);
                if (out.size() >= maxPois) { break; }
            }
        }
        return out;
    }

    // "fast_food" -> "Fast food"
    private function prettify(s as String) as String {
        var out = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i];
            if (ch == '_') {
                out += " ";
            } else {
                out += ch;
            }
        }
        if (out.length() > 1) {
            out = out.substring(0, 1).toUpper() + out.substring(1, out.length());
        }
        return out;
    }

    // ---- POI detail (full OSM tags for the detail page) ----

    private function detailKeyFor(p as Poi) as String? {
        if (p.osmType.length() == 0 || p.osmId.length() == 0) { return null; }
        return p.osmType + "/" + p.osmId;
    }

    // Full tag dictionary for a POI, or null if not fetched yet.
    function poiDetail(p as Poi) as Dictionary? {
        var key = detailKeyFor(p);
        if (key == null) { return null; }
        var v = _poiDetail.get(key);
        return (v instanceof Dictionary) ? v : null;
    }

    // Fetch the focused element's full tags on demand. No-op if already loaded,
    // a request is in flight, or it was attempted very recently.
    function requestPoiDetail(p as Poi) as Void {
        var key = detailKeyFor(p);
        if (key == null) { return; }
        if (_poiDetail.get(key) != null) { return; }
        if (_fetchPending || _detailPending) { return; }
        var now = Time.now().value();
        if (now - _lastDetailSec < 4) { return; }
        _detailPending = true;
        _lastDetailSec = now;
        _detailKey = key;
        var q = "[out:json][timeout:25];" + p.osmType + "(" + p.osmId + ");out tags;";
        Communications.makeWebRequest(OVERPASS_MIRRORS[_opIndex], {"data" => q},
                                      overpassOptions(), method(:onDetailResponse));
    }

    function onDetailResponse(code as Number, data as Dictionary or String or Null) as Void {
        _detailPending = false;
        var key = _detailKey;
        _detailKey = null;
        if (key == null) { return; }
        if (code == 200 && data instanceof Dictionary) {
            var tags = {} as Dictionary;
            var elements = data["elements"];
            if (elements instanceof Array && elements.size() > 0) {
                var el = elements[0];
                if (el instanceof Dictionary && el["tags"] instanceof Dictionary) {
                    tags = el["tags"];
                }
            }
            _poiDetail.put(key, tags); // store (possibly empty) = loaded
        }
        // On transient failure, leave it unset so the detail page retries.
        WatchUi.requestUpdate();
    }

    // ---- helpers ----

    private function numToD(v) as Double? {
        if (v instanceof Double) { return v; }
        if (v instanceof Float || v instanceof Number || v instanceof Long) {
            return v.toDouble();
        }
        return null;
    }
}
