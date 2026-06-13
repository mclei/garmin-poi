import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.WatchUi;

// Public Overpass mirrors. The main overpass-api.de instance intermittently
// serves a 406 HTML page from one of its load-balanced backends; the watch
// cannot parse that as JSON and reports error -400. We rotate to the next
// mirror on any failed request so a transient failure recovers quickly.
const OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.osm.ch/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter"
];
const OPENSKY_URL = "https://opensky-network.org/api/states/all";

const MAX_AIRCRAFT = 25;

// Central application state: position, heading, POI data and fetch logic.
class PoiModel {

    // Position / heading
    public var lat as Double?;
    public var lon as Double?;
    public var gpsQuality as Number;
    public var headingDeg as Float;

    // Data
    public var pois as Array<Poi>;       // land POIs, distance-sorted
    public var aircraft as Array<Poi>;
    public var visible as Array<Poi>;    // filtered union, distance-sorted
    public var targetPoi as Poi?;        // user-locked target

    // Status
    public var poiStatus as Number;
    public var poiError as Number;
    public var airStatus as Number;
    public var airError as Number;

    // Settings
    public var radiusM as Number;
    public var maxPois as Number;
    public var airRefreshSec as Number;
    public var catEnabled as Array<Boolean>;

    private var _fetchPending as Boolean;
    private var _airPending as Boolean;
    private var _needPoiFetch as Boolean;
    private var _lastPoiAttemptSec as Number;
    private var _lastAirAttemptSec as Number;
    private var _fetchLat as Double?;
    private var _fetchLon as Double?;
    private var _fetchedMask as Number;  // land categories included in last fetch
    private var _opIndex as Number;      // current Overpass mirror
    private var _dirty as Boolean;

    function initialize() {
        lat = null;
        lon = null;
        gpsQuality = 0;
        headingDeg = 0.0;
        pois = [] as Array<Poi>;
        aircraft = [] as Array<Poi>;
        visible = [] as Array<Poi>;
        targetPoi = null;
        poiStatus = STATUS_IDLE;
        poiError = 0;
        airStatus = STATUS_IDLE;
        airError = 0;
        radiusM = 5000;
        maxPois = 40;
        airRefreshSec = 30;
        catEnabled = new Array<Boolean>[NUM_CATS];
        for (var c = 0; c < NUM_CATS; c++) {
            catEnabled[c] = PoiCat.defaultEnabled(c);
        }
        _fetchPending = false;
        _airPending = false;
        _needPoiFetch = false;
        _lastPoiAttemptSec = 0;
        _lastAirAttemptSec = 0;
        _fetchLat = null;
        _fetchLon = null;
        _fetchedMask = 0;
        _opIndex = 0;
        _dirty = true;
        reloadSettings();
    }

    function start() as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS,
                                      method(:onPosition));
    }

    function stop() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE,
                                      method(:onPosition));
    }

    // ---- settings ----

    function reloadSettings() as Void {
        radiusM = getNumProp("radiusMeters", 5000);
        if (radiusM < 500) { radiusM = 500; }
        if (radiusM > 10000) { radiusM = 10000; }
        maxPois = getNumProp("maxPois", 40);
        if (maxPois < 10) { maxPois = 10; }
        if (maxPois > 100) { maxPois = 100; }
        airRefreshSec = getNumProp("aircraftRefreshSec", 30);
        if (airRefreshSec < 15) { airRefreshSec = 15; }
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
        _lastAirAttemptSec = 0;
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
            if (info.accuracy != null) {
                gpsQuality = info.accuracy as Number;
            }
            updateDerived();
        }
    }

    // Called ~5x/s from the main view timer
    function tick() as Void {
        var si = Sensor.getInfo();
        if (si != null && si.heading != null) {
            headingDeg = GeoUtils.normDeg(Math.toDegrees(si.heading).toFloat());
        }
        if (lat == null) { return; }
        var now = Time.now().value();
        maybeFetchPois(now);
        maybeFetchAircraft(now);
        if (_dirty) { rebuildVisible(); }
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
        for (var i = 0; i < aircraft.size(); i++) {
            var p = aircraft[i];
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
        for (var i = 0; i < pois.size(); i++) {
            var p = pois[i];
            if (catEnabled[p.category]) { out.add(p); }
        }
        if (catEnabled[CAT_AIRCRAFT]) {
            for (var i = 0; i < aircraft.size(); i++) {
                out.add(aircraft[i]);
            }
        }
        GeoUtils.sortByDistance(out);
        visible = out;
        var t = targetPoi;
        if (t != null && !catEnabled[t.category]) {
            targetPoi = null;
        }
        _dirty = false;
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
            if (catEnabled[c]) { return true; }
        }
        return false;
    }

    // ---- Overpass (OpenStreetMap POIs) ----

    private function maybeFetchPois(now as Number) as Void {
        if (_fetchPending || _airPending) { return; }
        if (!anyLandCatEnabled()) { return; }
        var since = now - _lastPoiAttemptSec;
        var doFetch = false;
        if (_fetchLat == null) {
            // first fix: fetch right away (attempt timestamp paces retries)
            doFetch = (since >= 5);
        } else {
            var moved = GeoUtils.distanceM(lat as Double, lon as Double,
                                           _fetchLat as Double, _fetchLon as Double);
            if (_needPoiFetch && since >= 10) {
                doFetch = true;
            } else if (poiStatus == STATUS_ERROR && since >= 8) {
                doFetch = true;
            } else if (moved > 400.0 && since >= 60) {
                doFetch = true;
            }
        }
        if (doFetch) { fetchPois(now); }
    }

    private function fetchPois(now as Number) as Void {
        _fetchPending = true;
        poiStatus = STATUS_LOADING;
        _lastPoiAttemptSec = now;
        _fetchLat = lat;
        _fetchLon = lon;
        _needPoiFetch = false;
        var mask = 0;
        for (var c = 0; c < NUM_LAND_CATS; c++) {
            if (catEnabled[c]) { mask |= (1 << c); }
        }
        // A broad nwr[historic] query also returns castles/ruins, so mark them
        // covered to avoid a redundant refetch when those toggles flip on.
        if ((mask & (1 << CAT_MONUMENT)) != 0) {
            mask |= (1 << CAT_CASTLE) | (1 << CAT_RUINS);
        }
        _fetchedMask = mask;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        var url = OVERPASS_ENDPOINTS[_opIndex % OVERPASS_ENDPOINTS.size()];
        Communications.makeWebRequest(url, {"data" => buildQuery()},
                                      options, method(:onPoiResponse));
    }

    private function buildQuery() as String {
        var la = (lat as Double).format("%.5f");
        var lo = (lon as Double).format("%.5f");
        var r = radiusM.toString();
        var around = "(around:" + r + "," + la + "," + lo + ");";
        // restaurants beyond 2 km are rarely interesting and bloat the response
        var rFood = (radiusM < 2000) ? radiusM : 2000;
        var aroundFood = "(around:" + rFood.toString() + "," + la + "," + lo + ");";
        var q = "[out:json][timeout:10];(";
        // Historic: a broad nwr[historic] covers monuments/memorials and is
        // classified down to castles/ruins; if only the narrow toggles are on,
        // fetch just those subsets.
        if (catEnabled[CAT_MONUMENT]) {
            q += "nwr[historic]" + around;
        } else {
            if (catEnabled[CAT_CASTLE]) {
                q += "nwr[historic~\"^(castle|fort|fortress|city_gate|citadel|castle_wall|manor|palace)$\"]" + around;
            }
            if (catEnabled[CAT_RUINS]) {
                q += "nwr[historic~\"^(ruins|archaeological_site)$\"]" + around;
            }
        }
        if (catEnabled[CAT_VIEWPOINT]) {
            q += "nwr[tourism~\"^(attraction|viewpoint)$\"]" + around;
        }
        // Food & drink (radius-capped): build the amenity alternation from the
        // enabled sub-toggles.
        var food = "";
        if (catEnabled[CAT_RESTAURANT]) { food += "restaurant|"; }
        if (catEnabled[CAT_CAFE]) { food += "cafe|fast_food|ice_cream|"; }
        if (catEnabled[CAT_BAR]) { food += "bar|pub|biergarten|"; }
        if (food.length() > 0) {
            food = food.substring(0, food.length() - 1); // drop trailing '|'
            q += "nwr[amenity~\"^(" + food + ")$\"]" + aroundFood;
        }
        if (catEnabled[CAT_MUSEUM]) {
            q += "nwr[tourism~\"^(museum|gallery|artwork)$\"]" + around;
        }
        if (catEnabled[CAT_THEATRE]) {
            q += "nwr[amenity~\"^(theatre|cinema|arts_centre)$\"]" + around;
        }
        if (catEnabled[CAT_WORSHIP]) {
            q += "nwr[amenity=place_of_worship]" + around;
        }
        q += ");out center qt 120;";
        return q;
    }

    function onPoiResponse(code as Number, data as Dictionary or String or Null) as Void {
        _fetchPending = false;
        if (code == 200 && data instanceof Dictionary) {
            var elements = data["elements"];
            if (elements instanceof Array) {
                parseElements(elements);
                poiStatus = STATUS_IDLE;
                poiError = 0;
            } else {
                poiStatus = STATUS_ERROR;
                poiError = -1;
                _opIndex = (_opIndex + 1) % OVERPASS_ENDPOINTS.size();
            }
        } else {
            poiStatus = STATUS_ERROR;
            poiError = code;
            // Rotate to the next mirror; a 406/5xx/parse error on one backend
            // usually succeeds on another.
            _opIndex = (_opIndex + 1) % OVERPASS_ENDPOINTS.size();
        }
        WatchUi.requestUpdate();
    }

    private function parseElements(elements as Array) as Void {
        var fresh = [] as Array<Poi>;
        for (var i = 0; i < elements.size(); i++) {
            var el = elements[i];
            if (!(el instanceof Dictionary)) { continue; }
            var tags = el["tags"];
            if (!(tags instanceof Dictionary)) { continue; }
            var plat = numToD(el["lat"]);
            var plon = numToD(el["lon"]);
            if (plat == null) {
                var c = el["center"];
                if (c instanceof Dictionary) {
                    plat = numToD(c["lat"]);
                    plon = numToD(c["lon"]);
                }
            }
            if (plat == null || plon == null) { continue; }
            var cd = categorize(tags);
            if (cd == null) { continue; }
            var subtype = prettify(cd[1] as String);
            var name = tags["name"];
            if (!(name instanceof String) || name.length() == 0) {
                name = subtype;
            }
            fresh.add(new Poi(name, plat, plon, cd[0] as Number, subtype));
        }
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
    }

    private function categorize(tags as Dictionary) as Array? {
        var h = tags["historic"];
        if (h instanceof String) {
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
        var t = tags["tourism"];
        if (t instanceof String) {
            if (t.equals("attraction") || t.equals("viewpoint")) {
                return [CAT_VIEWPOINT, t];
            }
            if (t.equals("museum") || t.equals("gallery") || t.equals("artwork")) {
                return [CAT_MUSEUM, t];
            }
        }
        var a = tags["amenity"];
        if (a instanceof String) {
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

    // ---- OpenSky (live aircraft) ----

    private function maybeFetchAircraft(now as Number) as Void {
        if (_fetchPending || _airPending) { return; }
        if (!catEnabled[CAT_AIRCRAFT]) {
            if (aircraft.size() > 0) {
                aircraft = [] as Array<Poi>;
                _dirty = true;
            }
            return;
        }
        if (now - _lastAirAttemptSec < airRefreshSec) { return; }
        fetchAircraft(now);
    }

    private function fetchAircraft(now as Number) as Void {
        _airPending = true;
        airStatus = STATUS_LOADING;
        _lastAirAttemptSec = now;
        var la = lat as Double;
        var lo = lon as Double;
        var dLat = radiusM / 111320.0;
        var cosLat = Math.cos(Math.toRadians(la));
        if (cosLat < 0.05) { cosLat = 0.05; }
        var dLon = radiusM / (111320.0 * cosLat);
        var params = {
            "lamin" => (la - dLat).format("%.4f"),
            "lomin" => (lo - dLon).format("%.4f"),
            "lamax" => (la + dLat).format("%.4f"),
            "lomax" => (lo + dLon).format("%.4f")
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(OPENSKY_URL, params, options,
                                      method(:onAirResponse));
    }

    function onAirResponse(code as Number, data as Dictionary or String or Null) as Void {
        _airPending = false;
        if (code == 200 && data instanceof Dictionary) {
            var fresh = [] as Array<Poi>;
            var states = data["states"];
            if (states instanceof Array) {
                for (var i = 0; i < states.size(); i++) {
                    if (fresh.size() >= MAX_AIRCRAFT) { break; }
                    var s = states[i];
                    if (!(s instanceof Array) || s.size() < 11) { continue; }
                    // OpenSky state vector: 1=callsign, 5=lon, 6=lat,
                    // 7=baro alt (m), 8=on_ground, 9=velocity (m/s), 10=track
                    if (s[8] == true) { continue; }
                    var plat = numToD(s[6]);
                    var plon = numToD(s[5]);
                    if (plat == null || plon == null) { continue; }
                    var name = "Aircraft";
                    var cs = s[1];
                    if (cs instanceof String) {
                        var trimmed = trim(cs);
                        if (trimmed.length() > 0) { name = trimmed; }
                    }
                    var detail = "";
                    var alt = numToD(s[7]);
                    if (alt != null) {
                        detail += alt.toNumber().toString() + " m";
                    }
                    var vel = numToD(s[9]);
                    if (vel != null) {
                        if (detail.length() > 0) { detail += ", "; }
                        detail += (vel * 3.6).toNumber().toString() + " km/h";
                    }
                    var p = new Poi(name, plat, plon, CAT_AIRCRAFT, detail);
                    var tr = numToD(s[10]);
                    if (tr != null) { p.track = tr.toFloat(); }
                    fresh.add(p);
                }
            }
            aircraft = fresh;
            airStatus = STATUS_IDLE;
            airError = 0;
            updateDerived();
        } else {
            airStatus = STATUS_ERROR;
            airError = code;
        }
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

    private function trim(s as String) as String {
        var chars = s.toCharArray();
        var start = 0;
        var end = chars.size();
        while (start < end && chars[start] == ' ') { start++; }
        while (end > start && chars[end - 1] == ' ') { end--; }
        if (start == 0 && end == chars.size()) { return s; }
        return s.substring(start, end);
    }
}
