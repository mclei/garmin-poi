import Toybox.Lang;

// POI categories. Indices 0..NUM_LAND_CATS-1 are fetched from OpenStreetMap
// via Overpass; CAT_AIRCRAFT comes from OpenSky. The order here must match
// the parallel arrays in module PoiCat and the defaults in PoiModel.
const CAT_MONUMENT   = 0;  // historic catch-all: monuments, memorials, other historic
const CAT_CASTLE     = 1;  // castles, forts, city gates, palaces
const CAT_RUINS      = 2;  // ruins, archaeological sites
const CAT_VIEWPOINT  = 3;  // viewpoints, generic tourist attractions
const CAT_RESTAURANT = 4;
const CAT_CAFE       = 5;  // cafe, fast food, ice cream
const CAT_BAR        = 6;  // bar, pub, biergarten
const CAT_MUSEUM     = 7;  // museum, gallery, artwork
const CAT_THEATRE    = 8;  // theatre, cinema, arts centre
const CAT_WORSHIP    = 9;  // places of worship
const CAT_AIRCRAFT   = 10; // live air traffic (OpenSky)
const NUM_CATS = 11;
const NUM_LAND_CATS = 10;  // categories fetched from Overpass

// Fetch status
const STATUS_IDLE = 0;
const STATUS_LOADING = 1;
const STATUS_ERROR = 2;

// A single point of interest (or aircraft)
class Poi {
    public var name as String;
    public var lat as Double;       // degrees
    public var lon as Double;       // degrees
    public var category as Number;  // CAT_*
    public var detail as String;    // subtype ("Castle") or aircraft altitude/speed
    public var distance as Float;   // meters from current position
    public var bearing as Float;    // degrees true, 0..360
    public var track as Float?;     // aircraft ground track, degrees true
    public var icao24 as String;    // aircraft Mode-S address (key for type lookup)
    public var osmType as String;   // "node"/"way"/"relation" (for detail fetch)
    public var osmId as String;     // OSM element id (for detail fetch)
    public var altM as Number;      // aircraft altitude in metres, -1 if unknown
    public var speedKmh as Number;  // aircraft ground speed in km/h, -1 if unknown

    function initialize(aName as String, aLat as Double, aLon as Double,
                        aCat as Number, aDetail as String) {
        name = aName;
        lat = aLat;
        lon = aLon;
        category = aCat;
        detail = aDetail;
        distance = 0.0;
        bearing = 0.0;
        track = null;
        icao24 = "";
        osmType = "";
        osmId = "";
        altM = -1;
        speedKmh = -1;
    }
}

// Per-category metadata, indexed by CAT_*.
module PoiCat {

    // radar dot / arrow colors (24-bit RGB)
    const COLORS = [
        0xFFCC00, // monument  - gold
        0xFF8800, // castle    - orange
        0xBB6600, // ruins     - brown
        0x33AAFF, // viewpoint - sky blue
        0x33DD33, // restaurant- green
        0xAADD00, // cafe      - lime
        0x00CC88, // bar       - teal
        0xFF66CC, // museum    - pink
        0xCC66FF, // theatre   - purple
        0xFF99AA, // worship   - rose
        0x00FFFF  // aircraft  - cyan
    ] as Array<Number>;

    const SHORT = [
        "mon", "cstl", "ruin", "view", "rest", "cafe",
        "bar", "mus", "thtr", "wrsp", "air"
    ] as Array<String>;

    const KEYS = [
        "catMonument", "catCastle", "catRuins", "catViewpoint",
        "catRestaurant", "catCafe", "catBar", "catMuseum",
        "catTheatre", "catWorship", "catAircraft"
    ] as Array<String>;

    // default on/off state when no stored property exists
    const DEFAULTS = [
        true, true, true, true, true, false,
        false, true, false, false, false
    ] as Array<Boolean>;

    function color(cat as Number) as Number { return COLORS[cat]; }
    function shortName(cat as Number) as String { return SHORT[cat]; }
    function propKey(cat as Number) as String { return KEYS[cat]; }
    function defaultEnabled(cat as Number) as Boolean { return DEFAULTS[cat]; }

    // String resource id for the category's display label.
    function label(cat as Number) as Symbol {
        var ids = [
            Rez.Strings.CatMonument, Rez.Strings.CatCastle,
            Rez.Strings.CatRuins, Rez.Strings.CatViewpoint,
            Rez.Strings.CatRestaurant, Rez.Strings.CatCafe,
            Rez.Strings.CatBar, Rez.Strings.CatMuseum,
            Rez.Strings.CatTheatre, Rez.Strings.CatWorship,
            Rez.Strings.CatAircraft
        ];
        return ids[cat];
    }
}
