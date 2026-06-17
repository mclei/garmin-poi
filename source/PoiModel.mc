import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.WatchUi;

// Land POIs come from Photon (komoot's OSM geocoder). Overpass is a best-effort
// database query engine whose public instances 406 / rate-limit (and the dead
// EU mirrors HANG instead of failing fast); Photon's /reverse endpoint is a
// lightweight "nearby by category" lookup on solid infrastructure - give it a
// lat/lon, a radius and osm_tag category filters and it returns compact,
// distance-sorted GeoJSON. application/json is the only text-ish type the watch
// accepts. Self-host github.com/komoot/photon to change endpoint.
const PHOTON_URL = "https://photon.komoot.io/reverse";

// Land POIs use an expanding search: start tight and widen only when nothing
// is found, up to 5 km. The starting radius depends on GPS precision (50 m on
// a good fix, wider when approximate) - see startLadderIndex(). In a dense
// city you stop almost immediately (tiny response); in open country you reach
// far, where there is little to return anyway.
const POI_RADII = [50, 100, 200, 500, 1000, 2000, 5000] as Array<Number>;

// Cap on returned features (Photon `limit`), so a dense stopping radius can't
// produce a response too large to parse on-watch. Photon features are ~350
// bytes each, so 30 is ~11 KB - within the JSON parse budget (50 was ~18 KB,
// too large). Photon already distance-sorts; we only show the nearest maxPois.
const POI_MAX_ELEMENTS = 30;

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

// Compass-calibration heuristic: a well-calibrated magnetometer reads a roughly
// constant field magnitude (~250-650 mG) in every orientation; hard/soft-iron
// error makes |mag| swing as the watch turns. We sample |mag| over a window but
// only trust the verdict once the accelerometer shows the watch was rotated
// through enough orientations (ORIENT_SPREAD_MIN, the summed range of the
// gravity unit-vector axes). MAG_VAR_THRESH is the (max-min)/mean swing above
// which calibration is judged suspect; MAG_LO/HI bound a plausible Earth-field
// magnitude in milliGauss (wide, since it varies by location).
const MAG_WINDOW = 50;            // samples per assessment (~10 s at 5 Hz)
const ORIENT_SPREAD_MIN = 0.6;
const MAG_VAR_THRESH = 0.40;
const MAG_LO = 200.0;
const MAG_HI = 800.0;

// Central application state: position, heading, POI data and fetch logic.
class PoiModel {

    // Position / heading
    public var lat as Double?;
    public var lon as Double?;
    public var gpsQuality as Number;  // latest Position.QUALITY_* (for display)
    public var headingDeg as Float;
    private var _haveHeading as Boolean;

    // Compass-calibration detection + debug readout.
    public var calSuspect as Boolean;     // true -> recommend recalibration
    public var magAvailable as Boolean;   // has the magnetometer ever returned data
    public var debugCompass as Boolean;   // show the on-screen debug readout
    public var dbgMin as Float;           // last window's |mag| min / max / swing / spread
    public var dbgMax as Float;
    public var dbgRatio as Float;
    public var dbgSpread as Float;
    private var _magMin as Float;
    private var _magMax as Float;
    private var _magSum as Float;
    private var _magCount as Number;
    private var _gMin as Array<Float>;    // gravity unit-vector axis min/max in window
    private var _gMax as Array<Float>;

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
    private var _oneShotCat as Number;   // temporary "show only this" category, -1 = off
    private var _oneShotPending as Boolean;
    private var _dirty as Boolean;

    function initialize() {
        lat = null;
        lon = null;
        gpsQuality = 0;
        headingDeg = 0.0;
        _haveHeading = false;
        calSuspect = false;
        magAvailable = false;
        debugCompass = true;
        dbgMin = 0.0;
        dbgMax = 0.0;
        dbgRatio = 0.0;
        dbgSpread = 0.0;
        _magMin = 0.0;
        _magMax = 0.0;
        _magSum = 0.0;
        _magCount = 0;
        _gMin = [0.0, 0.0, 0.0];
        _gMax = [0.0, 0.0, 0.0];
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
        _oneShotCat = -1;
        _oneShotPending = false;
        _dirty = true;
        reloadSettings();
    }

    function start() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS,
                                      method(:onPosition));
        // Deliberately NO cached/last-known seed: we wait for a genuinely precise
        // fix (QUALITY_GOOD) before showing anything, so POIs are never placed
        // around a stale or coarse position. onPosition accepts the first one.
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
        debugCompass = getBoolProp("debugCompass", true);
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
        var q = (info.accuracy != null) ? info.accuracy as Number
                                        : Position.QUALITY_NOT_AVAILABLE;
        gpsQuality = q;                 // tracked so the "acquiring" screen shows it
        // Accept only a precise fix. Connect IQ reports accuracy as a quality
        // tier (good/usable/poor/...), NOT metres, so QUALITY_GOOD is the closest
        // proxy for "precise". Coarser fixes are ignored; the last accepted
        // position is kept. The first accepted fix triggers the initial search
        // via maybeFetchPois (its _fetchLat == null branch).
        if (info.position == null || q < Position.QUALITY_GOOD) {
            return;
        }
        var deg = info.position.toDegrees();
        lat = deg[0].toDouble();
        lon = deg[1].toDouble();
        updateDerived();
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
        updateCompassCal(si);
        if (lat == null) { return; }
        maybeFetchPois(now);
        // Rebuilt every tick so the field-of-view filter tracks the heading as
        // you turn (re-filters the already-loaded POIs, no refetch).
        rebuildVisible();
    }

    // Estimate whether the compass calibration is bad by combining the
    // magnetometer and the accelerometer. |mag| should stay constant in every
    // orientation when calibrated; we accumulate its min/max/mean over a window
    // and only judge once the gravity vector (from accel) has swept through
    // enough orientations - otherwise a held-still watch trivially looks fine.
    private function updateCompassCal(si as Sensor.Info?) as Void {
        if (si == null) { return; }
        var a = si.accel;
        var m = si.mag;
        if (!(a instanceof Array) || a.size() < 3
            || !(m instanceof Array) || m.size() < 3) {
            return;   // magnetometer/accel not available this tick
        }
        magAvailable = true;
        var mx = m[0].toFloat();
        var my = m[1].toFloat();
        var mz = m[2].toFloat();
        var mag = Math.sqrt(mx * mx + my * my + mz * mz).toFloat();
        var ax = a[0].toFloat();
        var ay = a[1].toFloat();
        var az = a[2].toFloat();
        var an = Math.sqrt(ax * ax + ay * ay + az * az).toFloat();
        if (an < 1.0) { return; }
        var gx = ax / an;
        var gy = ay / an;
        var gz = az / an;

        if (_magCount == 0) {
            _magMin = mag; _magMax = mag;
            _gMin = [gx, gy, gz];
            _gMax = [gx, gy, gz];
        } else {
            if (mag < _magMin) { _magMin = mag; }
            if (mag > _magMax) { _magMax = mag; }
            if (gx < _gMin[0]) { _gMin[0] = gx; } if (gx > _gMax[0]) { _gMax[0] = gx; }
            if (gy < _gMin[1]) { _gMin[1] = gy; } if (gy > _gMax[1]) { _gMax[1] = gy; }
            if (gz < _gMin[2]) { _gMin[2] = gz; } if (gz > _gMax[2]) { _gMax[2] = gz; }
        }
        _magSum += mag;
        _magCount++;

        if (_magCount >= MAG_WINDOW) {
            var spread = (_gMax[0] - _gMin[0]) + (_gMax[1] - _gMin[1])
                       + (_gMax[2] - _gMin[2]);
            var mean = _magSum / _magCount;
            var ratio = (mean > 1.0) ? (_magMax - _magMin) / mean : 0.0;
            dbgMin = _magMin;
            dbgMax = _magMax;
            dbgRatio = ratio;
            dbgSpread = spread;
            // Only update the verdict if the watch was actually rotated enough.
            if (spread >= ORIENT_SPREAD_MIN) {
                calSuspect = (mean < MAG_LO) || (mean > MAG_HI)
                          || (ratio > MAG_VAR_THRESH);
            }
            _magCount = 0;
            _magSum = 0.0;
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

    // ---- Photon (OpenStreetMap POIs) ----

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
        // Retry after a transient failure (e.g. Photon briefly rate-limiting).
        // Short delay so a hiccup clears quickly.
        if (poiStatus == STATUS_ERROR && since >= 3) {
            fetchPois();
            return;
        }
        if (fresh) {
            _ladderIdx = startLadderIndex();
            fetchPois();
        }
    }

    // Starting radius for the expanding search. We only accept precise (GOOD)
    // fixes, so a tight 50 m start is always justified; the ladder widens from
    // there if too few POIs are found.
    private function startLadderIndex() as Number {
        // Only precise (GOOD) fixes are accepted, so always start tight at 50 m.
        return 0;
    }

    // Human-readable current GPS precision, shown on the "acquiring" screen
    // while waiting for a precise fix.
    function gpsQualityLabel() as String {
        var q = gpsQuality;
        if (q >= Position.QUALITY_GOOD)       { return "good"; }
        if (q >= Position.QUALITY_USABLE)     { return "usable"; }
        if (q >= Position.QUALITY_POOR)       { return "poor"; }
        if (q == Position.QUALITY_LAST_KNOWN) { return "last known"; }
        return "no signal";
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
        Communications.makeWebRequest(buildPhotonUrl(POI_RADII[_ladderIdx]),
                                      {}, httpJsonOptions(), method(:onPoiResponse));
    }

    private function httpJsonOptions() as Dictionary {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // Build the Photon /reverse URL: nearest features within `radius` metres
    // (Photon takes km), filtered to the enabled categories via osm_tag. Several
    // osm_tag params are OR'd together; the whole query string is built into the
    // URL (with an empty params dict) because a request Dictionary can't hold the
    // repeated osm_tag key.
    private function buildPhotonUrl(radius as Number) as String {
        var la = (lat as Double).format("%.5f");
        var lo = (lon as Double).format("%.5f");
        var km = (radius / 1000.0).format("%.3f");
        var url = PHOTON_URL + "?lat=" + la + "&lon=" + lo
                + "&radius=" + km + "&limit=" + POI_MAX_ELEMENTS.toString();
        // Historic: a broad `historic` (key only) covers monuments/memorials and
        // is classified down to castles/ruins; if only the narrow toggles are on,
        // request just those subtype values.
        if (effectiveCatEnabled(CAT_MONUMENT)) {
            url += tag("historic");
        } else {
            if (effectiveCatEnabled(CAT_CASTLE)) {
                url += tag("historic:castle") + tag("historic:fort")
                     + tag("historic:fortress") + tag("historic:city_gate")
                     + tag("historic:citadel") + tag("historic:castle_wall")
                     + tag("historic:manor") + tag("historic:palace");
            }
            if (effectiveCatEnabled(CAT_RUINS)) {
                url += tag("historic:ruins") + tag("historic:archaeological_site");
            }
        }
        if (effectiveCatEnabled(CAT_VIEWPOINT)) {
            url += tag("tourism:attraction") + tag("tourism:viewpoint")
                 + tag("tourism:zoo") + tag("tourism:theme_park")
                 + tag("tourism:aquarium")
                 + tag("man_made:tower") + tag("man_made:lighthouse")
                 + tag("man_made:windmill") + tag("man_made:obelisk");
        }
        if (effectiveCatEnabled(CAT_NATURE)) {
            url += tag("leisure:park") + tag("leisure:garden")
                 + tag("leisure:nature_reserve")
                 + tag("natural:peak") + tag("natural:waterfall")
                 + tag("natural:cave_entrance") + tag("natural:spring");
        }
        if (effectiveCatEnabled(CAT_RESTAURANT)) {
            url += tag("amenity:restaurant");
        }
        if (effectiveCatEnabled(CAT_CAFE)) {
            url += tag("amenity:cafe") + tag("amenity:fast_food")
                 + tag("amenity:ice_cream");
        }
        if (effectiveCatEnabled(CAT_BAR)) {
            url += tag("amenity:bar") + tag("amenity:pub") + tag("amenity:biergarten");
        }
        if (effectiveCatEnabled(CAT_MUSEUM)) {
            url += tag("tourism:museum") + tag("tourism:gallery")
                 + tag("tourism:artwork");
        }
        if (effectiveCatEnabled(CAT_THEATRE)) {
            url += tag("amenity:theatre") + tag("amenity:cinema")
                 + tag("amenity:arts_centre");
        }
        if (effectiveCatEnabled(CAT_WORSHIP)) {
            url += tag("amenity:place_of_worship");
        }
        return url;
    }

    private function tag(t as String) as String {
        return "&osm_tag=" + t;
    }

    function onPoiResponse(code as Number, data as Dictionary or String or Null) as Void {
        _fetchPending = false;
        if (code == 200 && data instanceof Dictionary) {
            var fresh = parseElements(data["features"]);
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
            // Transient failure (Photon rate-limiting, or -104 no phone).
            // maybeFetchPois retries shortly; the status line shows "retrying...".
            poiStatus = STATUS_ERROR;
            poiError = code;
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

    // Parse Photon's GeoJSON FeatureCollection. Each feature is:
    //   {geometry:{coordinates:[lon,lat]},
    //    properties:{osm_type:"N"/"W"/"R", osm_id, osm_key, osm_value, name,
    //                street, housenumber, city, postcode, ...}}
    private function parseElements(features) as Array<Poi> {
        var out = [] as Array<Poi>;
        if (!(features instanceof Array)) { return out; }
        for (var i = 0; i < features.size(); i++) {
            var el = features[i];
            if (!(el instanceof Dictionary)) { continue; }
            var props = el["properties"];
            if (!(props instanceof Dictionary)) { continue; }
            var geom = el["geometry"];
            if (!(geom instanceof Dictionary)) { continue; }
            var coords = geom["coordinates"];
            if (!(coords instanceof Array) || coords.size() < 2) { continue; }
            var plon = numToD(coords[0]);   // GeoJSON order is [lon, lat]
            var plat = numToD(coords[1]);
            if (plat == null || plon == null) { continue; }
            var cd = categorizeKv(strOf(props["osm_key"]), strOf(props["osm_value"]));
            if (cd == null) { continue; }
            var subtype = prettify(cd[1] as String);
            var name = strOf(props["name"]);
            if (name.length() == 0) { name = subtype; }
            var p = new Poi(name, plat, plon, cd[0] as Number, subtype);
            p.osmType = strOf(props["osm_type"]);
            var idv = props["osm_id"];
            p.osmId = (idv != null) ? idv.toString() : "";
            p.addr = joinAddr(props);
            out.add(p);
        }
        return out;
    }

    private function strOf(v) as String {
        return (v instanceof String) ? v : "";
    }

    // Join Photon's address fields into "Street 12, City".
    private function joinAddr(props as Dictionary) as String {
        var street = strOf(props["street"]);
        var num = strOf(props["housenumber"]);
        var city = strOf(props["city"]);
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

    // Classify from Photon's osm_key / osm_value (empty = absent).
    private function categorizeKv(key as String, value as String) as Array? {
        if (key.equals("historic")) {
            if (value.equals("castle") || value.equals("fort")
                || value.equals("fortress") || value.equals("city_gate")
                || value.equals("citadel") || value.equals("castle_wall")
                || value.equals("manor") || value.equals("palace")) {
                return [CAT_CASTLE, value];
            }
            if (value.equals("ruins") || value.equals("archaeological_site")) {
                return [CAT_RUINS, value];
            }
            return [CAT_MONUMENT, value]; // monuments, memorials, other historic
        }
        if (key.equals("tourism")) {
            if (value.equals("attraction") || value.equals("viewpoint")
                || value.equals("zoo") || value.equals("theme_park")
                || value.equals("aquarium")) {
                return [CAT_VIEWPOINT, value];
            }
            if (value.equals("museum") || value.equals("gallery")
                || value.equals("artwork")) {
                return [CAT_MUSEUM, value];
            }
        }
        if (key.equals("man_made")) {
            if (value.equals("tower") || value.equals("lighthouse")
                || value.equals("windmill") || value.equals("obelisk")) {
                return [CAT_VIEWPOINT, value];
            }
        }
        if (key.equals("leisure")) {
            if (value.equals("park") || value.equals("garden")
                || value.equals("nature_reserve")) {
                return [CAT_NATURE, value];
            }
        }
        if (key.equals("natural")) {
            if (value.equals("peak") || value.equals("waterfall")
                || value.equals("cave_entrance") || value.equals("spring")) {
                return [CAT_NATURE, value];
            }
        }
        if (key.equals("amenity")) {
            if (value.equals("restaurant")) { return [CAT_RESTAURANT, value]; }
            if (value.equals("cafe") || value.equals("fast_food")
                || value.equals("ice_cream")) {
                return [CAT_CAFE, value];
            }
            if (value.equals("bar") || value.equals("pub")
                || value.equals("biergarten")) {
                return [CAT_BAR, value];
            }
            if (value.equals("theatre") || value.equals("cinema")
                || value.equals("arts_centre")) {
                return [CAT_THEATRE, value];
            }
            if (value.equals("place_of_worship")) { return [CAT_WORSHIP, value]; }
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

    // ---- helpers ----

    private function numToD(v) as Double? {
        if (v instanceof Double) { return v; }
        if (v instanceof Float || v instanceof Number || v instanceof Long) {
            return v.toDouble();
        }
        return null;
    }
}
