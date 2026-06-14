import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.WatchUi;

const OVERPASS_URL = "https://overpass-api.de/api/interpreter";
const OPENSKY_URL = "https://opensky-network.org/api/states/all";

// OpenSky has no aircraft type or destination, so the focused aircraft's type
// (by Mode-S address) and route (by callsign) are resolved on demand from the
// free, keyless adsbdb.com and cached. Only the focused aircraft is looked up.
const ADSBDB_AIRCRAFT_URL = "https://api.adsbdb.com/v0/aircraft/";
const ADSBDB_CALLSIGN_URL = "https://api.adsbdb.com/v0/callsign/";

// Land POIs use an expanding search: start tight and widen only when nothing
// is found, up to 5 km. In a dense city you stop at 200 m (tiny response); in
// open country you reach far, where there is little to return anyway. This is
// what keeps the response small enough for the watch to parse everywhere.
const POI_RADII = [200, 500, 1000, 2000, 5000] as Array<Number>;

// Hard cap on returned rows, purely so a dense stopping radius can't produce a
// response too large to parse. No "qt" sort here: quadtile order biases the
// capped set to one corner; plain id order is geographically even and we
// distance-sort on the device regardless.
const POI_MAX_ELEMENTS = 250;

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
    private var _ladderIdx as Number;    // current step in POI_RADII expanding search
    private var _dirty as Boolean;

    // Aircraft detail caches (resolved lazily from adsbdb for the focused plane)
    private var _acType as Dictionary;   // icao24 -> type label ("" = unknown)
    private var _acRoute as Dictionary;  // callsign -> route label ("" = unknown)
    private var _acInfo as Dictionary;   // icao24 -> raw aircraft fields dict
    private var _acRouteInfo as Dictionary; // callsign -> raw flightroute dict
    private var _metaPending as Boolean;
    private var _lastMetaSec as Number;
    private var _metaTypeKey as String?;   // icao24 of in-flight type request
    private var _metaRouteKey as String?;  // callsign of in-flight route request

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
        _ladderIdx = 0;
        _dirty = true;
        _acType = {} as Dictionary;
        _acRoute = {} as Dictionary;
        _acInfo = {} as Dictionary;
        _acRouteInfo = {} as Dictionary;
        _metaPending = false;
        _lastMetaSec = 0;
        _metaTypeKey = null;
        _metaRouteKey = null;
        _poiDetail = {} as Dictionary;
        _detailPending = false;
        _detailKey = null;
        _lastDetailSec = 0;
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
        maybeResolveAircraft(now);
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
        // Retry the current radius step after a transient failure.
        if (poiStatus == STATUS_ERROR && since >= 8) {
            fetchPois();
            return;
        }
        // Start a fresh expanding search (from the tightest radius) on the
        // first fix, a filter/refresh request, or after moving far.
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
        if (fresh) {
            _ladderIdx = 0;
            fetchPois();
        }
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
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };
        Communications.makeWebRequest(OVERPASS_URL,
                                      {"data" => buildQuery(POI_RADII[_ladderIdx])},
                                      options, method(:onPoiResponse));
    }

    // CSV output requesting only the columns we use keeps the response tiny
    // (~50 bytes/row vs ~550 for full JSON), which is what lets the watch parse
    // it. Columns: type, lat, lon, name, historic, tourism, amenity (tab-sep).
    private function buildQuery(radius as Number) as String {
        var la = (lat as Double).format("%.5f");
        var lo = (lon as Double).format("%.5f");
        var ar = "(around:" + radius.toString() + "," + la + "," + lo + ");";
        var q = "[out:csv(::type,::id,::lat,::lon,name,historic,tourism,amenity;false)]"
              + "[timeout:25];(";
        // Historic: a broad nwr[historic] covers monuments/memorials and is
        // classified down to castles/ruins; if only the narrow toggles are on,
        // fetch just those subsets.
        if (catEnabled[CAT_MONUMENT]) {
            q += "nwr[historic]" + ar;
        } else {
            if (catEnabled[CAT_CASTLE]) {
                q += "nwr[historic~\"^(castle|fort|fortress|city_gate|citadel|castle_wall|manor|palace)$\"]" + ar;
            }
            if (catEnabled[CAT_RUINS]) {
                q += "nwr[historic~\"^(ruins|archaeological_site)$\"]" + ar;
            }
        }
        if (catEnabled[CAT_VIEWPOINT]) {
            q += "nwr[tourism~\"^(attraction|viewpoint)$\"]" + ar;
        }
        var food = "";
        if (catEnabled[CAT_RESTAURANT]) { food += "restaurant|"; }
        if (catEnabled[CAT_CAFE]) { food += "cafe|fast_food|ice_cream|"; }
        if (catEnabled[CAT_BAR]) { food += "bar|pub|biergarten|"; }
        if (food.length() > 0) {
            food = food.substring(0, food.length() - 1); // drop trailing '|'
            q += "nwr[amenity~\"^(" + food + ")$\"]" + ar;
        }
        if (catEnabled[CAT_MUSEUM]) {
            q += "nwr[tourism~\"^(museum|gallery|artwork)$\"]" + ar;
        }
        if (catEnabled[CAT_THEATRE]) {
            q += "nwr[amenity~\"^(theatre|cinema|arts_centre)$\"]" + ar;
        }
        if (catEnabled[CAT_WORSHIP]) {
            q += "nwr[amenity=place_of_worship]" + ar;
        }
        q += ");out center " + POI_MAX_ELEMENTS.toString() + ";";
        return q;
    }

    function onPoiResponse(code as Number, data as Dictionary or String or Null) as Void {
        _fetchPending = false;
        if (code == 200 && data instanceof String) {
            var fresh = parseCsv(data);
            if (fresh.size() > 0) {
                finalizePois(fresh);
            } else if (_ladderIdx < POI_RADII.size() - 1) {
                // Nothing within this radius: widen the search and try again.
                _ladderIdx++;
                fetchPois();
                return;
            } else {
                // Nothing even within the largest radius.
                pois = [] as Array<Poi>;
                _dirty = true;
                poiStatus = STATUS_IDLE;
                poiError = 0;
            }
        } else {
            // Transient (overpass-api.de intermittently 406s/504s); retried by
            // maybeFetchPois against the same radius after a short backoff.
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

    // Parse tab-separated CSV rows into Poi objects in a single pass.
    private function parseCsv(text as String) as Array<Poi> {
        var out = [] as Array<Poi>;
        var chars = text.toCharArray();
        var n = chars.size();
        var cols = new Array<String>[8];
        for (var k = 0; k < 8; k++) { cols[k] = ""; }
        var field = 0;
        var cur = "";
        for (var i = 0; i <= n; i++) {
            var ch = (i < n) ? chars[i] : '\n';
            if (ch == '\t') {
                if (field < 8) { cols[field] = cur; }
                field++;
                cur = "";
            } else if (ch == '\n') {
                if (field < 8) { cols[field] = cur; }
                if (field >= 7) {            // a full row has 7 tabs / 8 columns
                    var poi = rowToPoi(cols);
                    if (poi != null) { out.add(poi); }
                }
                for (var k2 = 0; k2 < 8; k2++) { cols[k2] = ""; }
                field = 0;
                cur = "";
            } else if (ch != '\r') {
                cur += ch.toString();
            }
        }
        return out;
    }

    // cols = [type, id, lat, lon, name, historic, tourism, amenity]
    private function rowToPoi(cols as Array<String>) as Poi? {
        var plat = parseCoord(cols[2]);
        var plon = parseCoord(cols[3]);
        if (plat == null || plon == null) { return null; }
        var cd = categorizeTags(cols[5], cols[6], cols[7]);
        if (cd == null) { return null; }
        var subtype = prettify(cd[1] as String);
        var name = cols[4];
        if (name.length() == 0) { name = subtype; }
        var p = new Poi(name, plat, plon, cd[0] as Number, subtype);
        p.osmType = cols[0];
        p.osmId = cols[1];
        return p;
    }

    private function parseCoord(s as String) as Double? {
        if (s.length() == 0) { return null; }
        var f = s.toFloat();
        if (f == null) { return null; }
        return f.toDouble();
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
                    var icao = s[0];
                    if (icao instanceof String) { p.icao24 = trim(icao); }
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

    // ---- aircraft type/route resolution (adsbdb) ----

    // Resolved labels for the focused aircraft; null = not looked up yet,
    // "" = looked up but unknown, otherwise a display string.
    function aircraftType(icao24 as String) as String? {
        if (icao24.length() == 0) { return null; }
        return _acType.get(icao24);
    }

    function aircraftRoute(callsign as String) as String? {
        if (callsign.length() == 0) { return null; }
        return _acRoute.get(callsign);
    }

    private function maybeResolveAircraft(now as Number) as Void {
        if (!catEnabled[CAT_AIRCRAFT]) { return; }
        var f = focusedPoi();
        if (f == null || f.category != CAT_AIRCRAFT) { return; }
        resolveAircraftFor(f);
    }

    // Resolve type/route for a specific aircraft. Public so the detail page
    // (where the main view's timer is paused) can keep it progressing.
    function resolveAircraftFor(f as Poi) as Void {
        if (_metaPending || _fetchPending || _airPending) { return; }
        var now = Time.now().value();
        if (now - _lastMetaSec < 2) { return; }
        // One lookup per call: type first (by Mode-S), then route (by callsign).
        if (f.icao24.length() > 0 && _acType.get(f.icao24) == null) {
            _metaPending = true;
            _lastMetaSec = now;
            _metaTypeKey = f.icao24;
            Communications.makeWebRequest(ADSBDB_AIRCRAFT_URL + f.icao24, {},
                                          metaOptions(), method(:onTypeResponse));
            return;
        }
        if (f.name.length() > 0 && _acRoute.get(f.name) == null) {
            _metaPending = true;
            _lastMetaSec = now;
            _metaRouteKey = f.name;
            Communications.makeWebRequest(ADSBDB_CALLSIGN_URL + f.name, {},
                                          metaOptions(), method(:onRouteResponse));
        }
    }

    function aircraftInfo(icao24 as String) as Dictionary? {
        if (icao24.length() == 0) { return null; }
        var v = _acInfo.get(icao24);
        return (v instanceof Dictionary) ? v : null;
    }

    function flightInfo(callsign as String) as Dictionary? {
        if (callsign.length() == 0) { return null; }
        var v = _acRouteInfo.get(callsign);
        return (v instanceof Dictionary) ? v : null;
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
        if (_metaPending || _fetchPending || _airPending || _detailPending) { return; }
        var now = Time.now().value();
        if (now - _lastDetailSec < 4) { return; }
        _detailPending = true;
        _lastDetailSec = now;
        _detailKey = key;
        var q = "[out:json][timeout:25];" + p.osmType + "(" + p.osmId + ");out tags;";
        Communications.makeWebRequest(OVERPASS_URL, {"data" => q},
                                      metaOptions(), method(:onDetailResponse));
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

    private function metaOptions() as Dictionary {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    function onTypeResponse(code as Number, data as Dictionary or String or Null) as Void {
        _metaPending = false;
        var key = _metaTypeKey;
        _metaTypeKey = null;
        if (key == null) { return; }
        var label = ""; // cache "" on failure so we don't retry forever
        if (code == 200 && data instanceof Dictionary) {
            var resp = data["response"];
            if (resp instanceof Dictionary) {
                var ac = resp["aircraft"];
                if (ac instanceof Dictionary) {
                    label = buildTypeLabel(ac);
                    _acInfo.put(key, ac);
                }
            }
        }
        _acType.put(key, label);
        WatchUi.requestUpdate();
    }

    private function buildTypeLabel(ac as Dictionary) as String {
        var t = ac["icao_type"];
        if (!(t instanceof String) || t.length() == 0) { t = ac["type"]; }
        var label = "";
        var manuf = ac["manufacturer"];
        if (manuf instanceof String && manuf.length() > 0) { label = manuf; }
        if (t instanceof String && t.length() > 0) {
            label = (label.length() > 0) ? (label + " " + t) : t;
        }
        var owner = ac["registered_owner"];
        if (owner instanceof String && owner.length() > 0) {
            label = (label.length() > 0) ? (label + " - " + owner) : owner;
        }
        return label;
    }

    function onRouteResponse(code as Number, data as Dictionary or String or Null) as Void {
        _metaPending = false;
        var key = _metaRouteKey;
        _metaRouteKey = null;
        if (key == null) { return; }
        var label = "";
        if (code == 200 && data instanceof Dictionary) {
            var resp = data["response"];
            if (resp instanceof Dictionary) {
                var fr = resp["flightroute"];
                if (fr instanceof Dictionary) {
                    label = buildRouteLabel(fr);
                    _acRouteInfo.put(key, fr);
                }
            }
        }
        _acRoute.put(key, label);
        WatchUi.requestUpdate();
    }

    private function buildRouteLabel(fr as Dictionary) as String {
        var origin = airportField(fr["origin"], "iata_code");
        var dest = fr["destination"];
        var dCode = airportField(dest, "iata_code");
        var dCity = airportField(dest, "municipality");
        var label = "";
        if (origin.length() > 0) { label = origin + " "; }
        label += "-> ";
        if (dCode.length() > 0) { label += dCode; }
        if (dCity.length() > 0) { label += " " + dCity; }
        return label;
    }

    private function airportField(ap, field as String) as String {
        if (ap instanceof Dictionary) {
            var v = ap[field];
            if (v instanceof String) { return v; }
        }
        return "";
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
