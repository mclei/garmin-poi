import Toybox.Lang;

// POI categories, all fetched from OpenStreetMap via Photon. The order here
// must match the parallel arrays in module PoiCat and the defaults in PoiModel.
// Grouped logically: sights first, then food & drink. This order also drives
// the filter menu and the phone settings list (both iterate 0..NUM_CATS).
const CAT_VIEWPOINT  = 0;  // viewpoints, generic tourist attractions
const CAT_MONUMENT   = 1;  // historic catch-all: monuments, memorials, other historic
const CAT_CASTLE     = 2;  // castles, forts, city gates, palaces
const CAT_RUINS      = 3;  // ruins, archaeological sites
const CAT_WORSHIP    = 4;  // places of worship
const CAT_MUSEUM     = 5;  // museum, gallery, artwork
const CAT_THEATRE    = 6;  // theatre, cinema, arts centre
const CAT_RESTAURANT = 7;
const CAT_CAFE       = 8;  // cafe, fast food, ice cream
const CAT_BAR        = 9;  // bar, pub, biergarten
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
        0x33AAFF, // viewpoint - sky blue
        0xFFCC00, // monument  - gold
        0xFF8800, // castle    - orange
        0xBB6600, // ruins     - brown
        0xFF99AA, // worship   - rose
        0xFF66CC, // museum    - pink
        0xCC66FF, // theatre   - purple
        0x33DD33, // restaurant- green
        0xAADD00, // cafe      - lime
        0x00CC88  // bar       - teal
    ] as Array<Number>;

    const SHORT = [
        "view", "mon", "cstl", "ruin", "wrsp", "mus",
        "thtr", "rest", "cafe", "bar"
    ] as Array<String>;

    const KEYS = [
        "catViewpoint", "catMonument", "catCastle", "catRuins",
        "catWorship", "catMuseum", "catTheatre",
        "catRestaurant", "catCafe", "catBar"
    ] as Array<String>;

    // default on/off state when no stored property exists
    const DEFAULTS = [
        true, true, true, true, true, true,
        false, true, false, false
    ] as Array<Boolean>;

    function color(cat as Number) as Number { return COLORS[cat]; }
    function shortName(cat as Number) as String { return SHORT[cat]; }
    function propKey(cat as Number) as String { return KEYS[cat]; }
    function defaultEnabled(cat as Number) as Boolean { return DEFAULTS[cat]; }

    // String resource id for the category's display label.
    function label(cat as Number) as Symbol {
        var ids = [
            Rez.Strings.CatViewpoint, Rez.Strings.CatMonument,
            Rez.Strings.CatCastle, Rez.Strings.CatRuins,
            Rez.Strings.CatWorship, Rez.Strings.CatMuseum,
            Rez.Strings.CatTheatre, Rez.Strings.CatRestaurant,
            Rez.Strings.CatCafe, Rez.Strings.CatBar
        ];
        return ids[cat];
    }
}
