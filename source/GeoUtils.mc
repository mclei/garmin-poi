import Toybox.Lang;
import Toybox.Math;

module GeoUtils {

    const EARTH_R = 6371000.0d;

    // Great-circle distance in meters (haversine)
    function distanceM(lat1 as Double, lon1 as Double,
                       lat2 as Double, lon2 as Double) as Float {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dp = p2 - p1;
        var dl = Math.toRadians(lon2 - lon1);
        var sp = Math.sin(dp / 2);
        var sl = Math.sin(dl / 2);
        var a = sp * sp + Math.cos(p1) * Math.cos(p2) * sl * sl;
        var c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a));
        return (EARTH_R * c).toFloat();
    }

    // Initial bearing from point 1 to point 2, degrees true 0..360
    function bearingDeg(lat1 as Double, lon1 as Double,
                        lat2 as Double, lon2 as Double) as Float {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dl = Math.toRadians(lon2 - lon1);
        var y = Math.sin(dl) * Math.cos(p2);
        var x = Math.cos(p1) * Math.sin(p2)
              - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        return normDeg(Math.toDegrees(Math.atan2(y, x)).toFloat());
    }

    // Normalize an angle to 0..360
    function normDeg(d as Float) as Float {
        while (d < 0.0) { d += 360.0; }
        while (d >= 360.0) { d -= 360.0; }
        return d;
    }

    // Signed smallest difference a-b, in -180..180
    function angleDiff(a as Float, b as Float) as Float {
        var d = a - b;
        while (d > 180.0) { d -= 360.0; }
        while (d < -180.0) { d += 360.0; }
        return d;
    }

    function formatDistance(m as Float) as String {
        if (m < 1000.0) {
            return m.toNumber().toString() + " m";
        }
        return (m / 1000.0).format("%.1f") + " km";
    }

    function cardinal(deg as Float) as String {
        var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        var idx = ((normDeg(deg) + 22.5) / 45.0).toNumber() % 8;
        return dirs[idx];
    }

    // In-place insertion sort by Poi.distance (arrays here are small)
    function sortByDistance(arr as Array) as Void {
        for (var i = 1; i < arr.size(); i++) {
            var p = arr[i] as Poi;
            var j = i - 1;
            while (j >= 0 && (arr[j] as Poi).distance > p.distance) {
                arr[j + 1] = arr[j];
                j--;
            }
            arr[j + 1] = p;
        }
    }
}
