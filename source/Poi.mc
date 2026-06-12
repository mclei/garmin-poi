import Toybox.Graphics;
import Toybox.Lang;

// POI categories
const CAT_HISTORIC = 0;
const CAT_FOOD = 1;
const CAT_CULTURE = 2;
const CAT_AIRCRAFT = 3;
const NUM_CATS = 4;
const NUM_LAND_CATS = 3;   // categories fetched from Overpass

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
    }
}

module PoiCat {

    function color(cat as Number) as Number {
        if (cat == CAT_HISTORIC) { return Graphics.COLOR_YELLOW; }
        if (cat == CAT_FOOD)     { return Graphics.COLOR_GREEN; }
        if (cat == CAT_CULTURE)  { return Graphics.COLOR_PINK; }
        return 0x00FFFF; // aircraft: cyan
    }

    function shortName(cat as Number) as String {
        if (cat == CAT_HISTORIC) { return "hist"; }
        if (cat == CAT_FOOD)     { return "food"; }
        if (cat == CAT_CULTURE)  { return "cult"; }
        return "air";
    }

    // Property key for each category toggle
    function propKey(cat as Number) as String {
        if (cat == CAT_HISTORIC) { return "catHistoric"; }
        if (cat == CAT_FOOD)     { return "catFood"; }
        if (cat == CAT_CULTURE)  { return "catCulture"; }
        return "catAircraft";
    }
}
