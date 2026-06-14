# POI Finder — Garmin watch app

"What am I standing in front of?" — a Connect IQ watch app that shows the
nearest points of interest around you using GPS and the magnetic compass.
As you turn, a live arrow points at the POI you are facing, with its name
and distance. Built for the **Garmin Venu X1** (square display), works on
any modern Connect IQ device you add to the manifest.

## Features

- **Compass view**: rotating compass ring, nearby POIs as colored radar
  dots, and the POI you are currently facing (±35° cone) shown large with
  a direction arrow (green when you are pointing straight at it), distance
  and type.
- **Nearest list**: tap / swipe up for a distance-sorted list of everything
  nearby. Selecting an entry *locks it as target* — the arrow then keeps
  pointing at it until you clear the lock.
- **Categories** — each is an independent on/off toggle, available both on
  the watch (hold for menu → Filters) and in the phone settings. Connect IQ
  has no multi-select list widget, so "pick the categories you want" is done
  with one toggle per category:
  - Monuments & memorials — `historic=*` (the catch-all for historic features)
  - Castles & forts — `historic=castle/fort/city_gate/palace/…`
  - Ruins & archaeology — `historic=ruins/archaeological_site`
  - Viewpoints & attractions — `tourism=viewpoint/attraction`
  - Restaurants — `amenity=restaurant`
  - Cafés & fast food — `amenity=cafe/fast_food/ice_cream`
  - Bars & pubs — `amenity=bar/pub/biergarten`
  - Museums & galleries — `tourism=museum/gallery/artwork`
  - Theatres & cinemas — `amenity=theatre/cinema/arts_centre`
  - Places of worship — `amenity=place_of_worship`
  - Aircraft (live) — overhead air traffic. When you point at one, the main
    screen shows its **destination** and **aircraft type** (e.g. "FRA → SAW
    Istanbul" / "Airbus A321 - Pegasus"), plus callsign, distance, altitude
    and speed. Type and route are looked up on demand for the focused plane.

  Defaults on: Monuments, Castles, Ruins, Viewpoints, Restaurants, Museums.
- **Range** — land POIs use an *expanding search* that widens only until
  something is found (up to 5 km). The starting radius tracks GPS precision:
  **50 m** on a good fix, ~200 m on a usable one, ~500 m while the position is
  still approximate — so a precise fix in a city shows exactly what's right in
  front of you. The query uses Overpass `convert` to return only the fields it
  needs, keeping the response small enough to parse on-watch. Aircraft use the
  configured radius (default 5 km).
- **Fast start** — on launch the app seeds from the cached last-known position
  so POIs load immediately while the GPS warms up. The status line shows a
  leading `~` until a precise fix arrives, then the list is refined to it.

## Data sources (free, no API keys)

| Data | Source | Notes |
|------|--------|-------|
| Land POIs | [Overpass API](https://overpass-api.de) (OpenStreetMap) | Several **global mirrors** (`overpass-api.de`, `kumi.systems`, `private.coffee`); a starting one is picked from your position and the app **fails over to the next on any error** (overpass-api.de in particular intermittently 406s). Fetched at most every ~60 s and after moving >400 m. The expanding radius keeps the JSON response small enough to parse on-watch. Edit `OVERPASS_MIRRORS` in `source/PoiModel.mc` to change the list. |
| Aircraft positions | [OpenSky Network](https://opensky-network.org) | Anonymous access has a daily request budget (~400 credits/day, 1–4 per call). Default refresh is 30 s; raise it in settings if you watch planes for hours. |
| Aircraft type & route | [adsbdb.com](https://www.adsbdb.com) | Free, keyless. OpenSky has no type/destination, so the **focused** aircraft's type (by Mode-S address) and route (by callsign) are fetched here and cached. Only the focused plane is looked up, so volume stays low. |

Requests go through the **paired phone** (Garmin Connect Mobile must be
running with internet access). Without the phone you'll see error `-104`.

## Project layout

```
manifest.xml            app manifest (watchapp, venux1)
monkey.jungle           build file
resources/              strings, properties, settings UI, launcher icon
scripts/make_icon.py    regenerates the launcher icon (stdlib-only Python)
source/
  PoiFinderApp.mc       app entry point
  PoiModel.mc           GPS, compass, Overpass + OpenSky fetching, state
  Poi.mc                POI class, categories
  GeoUtils.mc           distance/bearing math, formatting
  MainView.mc           compass/radar screen
  MainDelegate.mc       input handling
  PoiUi.mc              filter menu and nearest-POI list
```

## Building

### 1. Install the Connect IQ SDK

1. Install a Java runtime: `sudo apt install default-jre` (Linux) or any
   JRE 11+ on macOS/Windows.
2. Download the **Connect IQ SDK Manager** from
   <https://developer.garmin.com/connect-iq/sdk/> and run it.
3. In the SDK Manager: download the latest SDK (7.x/8.x) and, under
   *Devices*, download **Venu X1**.
4. Note the SDK path (e.g. `~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-...`)
   and add its `bin/` directory to your `PATH`.

Alternatively install the **Monkey C** extension in VS Code, which drives
the same SDK ("Monkey C: Verify Installation", then *Run → Build for
Device*).

### 2. Generate a developer key (once)

```sh
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
    -in developer_key.pem -out developer_key.der
```

### 3. Build

```sh
monkeyc -d venux1 -f monkey.jungle -o PoiFinder.prg -y developer_key.der
```

### 4. Run in the simulator (recommended first)

```sh
connectiq            # starts the simulator
monkeydo PoiFinder.prg venux1
```

In the simulator use *Simulation → Locations* to set a GPS position
(pick a city center so Overpass returns plenty of POIs).

### 5. Sideload to the watch

Connect the watch over USB (MTP) and copy `PoiFinder.prg` into the
watch's `GARMIN/Apps` folder. The app appears in the activity/app list.

## Usage

| Input | Action |
|-------|--------|
| **Tap the screen**, or the **Start/Enter button** | Open the **detail page** of the shown POI (scrollable: full description/tags for places, type + route for aircraft) |
| **Swipe in from the right edge** | Filters menu (settings) — category toggles + "Refresh now" |
| Swipe up | Nearest-POI list; select an entry opens its detail page |
| Long-press screen | Filters menu (only where the firmware emits it) |
| Back | Exit |

On the detail page: swipe up/down (or the buttons) to scroll, **Start** to
lock/unlock the POI as your target, **Back** to return.

On a sideloaded build the phone settings are unavailable, so the **Filters
menu is where you turn POI categories on and off** — open it with the Start
button or a right-edge swipe.

Status line at the bottom: current heading, POI count (or load/error
state), aircraft count when the aircraft category is enabled.

The launcher icon can be regenerated with `python3 scripts/make_icon.py`.

## Settings

Via Garmin Connect Mobile (or Connect IQ Store app) → POI Finder →
Settings: aircraft radius, max places, category toggles, aircraft refresh
interval. (Land POIs auto-expand 200 m→5 km and need no radius setting.)
Category toggles changed on the watch are persisted and synced back.

## CI (GitHub Actions)

`.github/workflows/build.yml` builds the app on every push/PR and uploads
`PoiFinder.prg` as a workflow artifact (download it from the run page and
sideload it). On `v*` tags it additionally exports the store package
(`PoiFinder.iq`).

It runs inside the community-maintained
[`ghcr.io/matco/connectiq-tester`](https://github.com/matco/connectiq-tester)
image, which bundles the Connect IQ SDK and the device files that Garmin's
SDK Manager otherwise only provides through a GUI login.

**Signing key**: by default each CI run generates a throwaway developer
key, which is fine for sideloading. To sign with *your* key (required if
you later upload to the Connect IQ Store, where all versions must use the
same key), add a repository secret named `CIQ_DEVELOPER_KEY` containing
the base64 of your DER key:

```sh
base64 -w0 developer_key.der   # paste output into the secret
```

To enable CI: `git init && git add . && git commit`, create a GitHub repo
and push — the workflow runs automatically.

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| `POI err -104` | Watch not connected to the phone / no internet |
| `POI err 406` / `-400` / `504` / `429` | A mirror failed (overpass-api.de 406s a lot, which surfaces as -400). The app fails over to the next mirror and retries every ~8 s; usually transient. |
| `air err 429` | OpenSky anonymous daily budget exhausted |
| `0 POI` everywhere | All categories disabled, or genuinely nothing within 5 km — open Filters (Start button) and enable categories |
| Compass frozen | Calibrate compass (figure-8 motion); Venu X1 has a magnetometer |

## Adding more devices

Add product ids to `manifest.xml` (e.g. `<iq:product id="venu3"/>`) and
download the matching device files in the SDK Manager. All drawing is
resolution-independent, so round displays work too.
