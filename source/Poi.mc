import Toybox.Lang;

// POI categories, all fetched from OpenStreetMap via Photon. The order here
// must match the parallel arrays in module PoiCat and the defaults in PoiModel.
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
const NUM_CATS = 10;
const NUM_LAND_CATS = 10;

// Fetch status
const STATUS_IDLE = 0;
const STATUS_LOADING = 1;
const STATUS_ERROR = 2;

// A single point of interest.
class Poi {
    public var name as String;
    public var lat as Double;       // degrees
    public var lon as Double;       // degrees
    public var category as Number;  // CAT_*
    public var detail as String;    // subtype, e.g. "Castle"
    public var distance as Float;   // meters from current position
    public var bearing as Float;    // degrees true, 0..360
    public var osmType as String;   // "N"/"W"/"R" from Photon (OSM element type)
    public var osmId as String;     // OSM element id
    public var addr as String;      // joined street address (from Photon), may be ""
    public var inView as Boolean;   // currently inside the field-of-view cone (hysteresis)

    function initialize(aName as String, aLat as Double, aLon as Double,
                        aCat as Number, aDetail as String) {
        name = aName;
        lat = aLat;
        lon = aLon;
        category = aCat;
        detail = aDetail;
        distance = 0.0;
        bearing = 0.0;
        osmType = "";
        osmId = "";
        addr = "";
        inView = false;
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
        0xFF99AA  // worship   - rose
    ] as Array<Number>;

    const SHORT = [
        "mon", "cstl", "ruin", "view", "rest", "cafe",
        "bar", "mus", "thtr", "wrsp"
    ] as Array<String>;

    const KEYS = [
        "catMonument", "catCastle", "catRuins", "catViewpoint",
        "catRestaurant", "catCafe", "catBar", "catMuseum",
        "catTheatre", "catWorship"
    ] as Array<String>;

    // default on/off state when no stored property exists
    const DEFAULTS = [
        true, true, true, true, true, false,
        false, true, false, true
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
            Rez.Strings.CatTheatre, Rez.Strings.CatWorship
        ];
        return ids[cat];
    }
}
