# Ahead — Garmin watch app

### The place in front of you

"What's that place I'm looking at?" — a Connect IQ watch app that names the
point of interest **in front of you** using GPS and the magnetic compass.
Point your wrist and the place you're facing is shown with its name, distance
and details; turn and it updates to whatever you now face. Built for the
**Garmin Venu X1**, and works on **round** models too (the UI is centered and
resolution‑independent; the detail page adapts its layout on round screens).
The manifest lists a range of current round + square watches; add more via the
SDK Manager.

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

  Defaults on: Monuments, Castles, Ruins, Viewpoints, Restaurants, Museums.
- **Field of view** — POIs are shown only when they're roughly in front
  of you (within ~45° of your heading, ~90° total). As you turn, the set
  re-filters live from the already-loaded data (no refetch), with hysteresis so
  POIs near the edge don't flicker.
- **Range** — an *expanding search* that widens until it has found enough POIs
  (about 10), or reaches 5 km. A tight radius with only a hit or two keeps
  widening so you get a useful set, not just the single closest thing. The starting radius tracks GPS precision: **50 m** on a good
  fix, ~200 m on a usable one, ~500 m while the position is still approximate —
  so a precise fix in a city shows exactly what's right in front of you. The
  query uses Overpass `convert` to return only the fields it needs, keeping the
  response small enough to parse on-watch.
- **Fast start** — on launch the app seeds from the cached last-known position
  so POIs load immediately while the GPS warms up. The status line shows a
  leading `~` until a precise fix arrives, then the list is refined to it.
- **Glance** — in the watch's glance carousel, Ahead shows the place in front
  of you ("Charles Bridge  120 m"). It fetches on demand *when it scrolls into
  view*: reads the last-known position and runs one small POI query (1.5 km,
  honouring your category toggles), then features the nearest place **within
  your compass field of view** (nearest overall if you're facing nothing). The
  name **marquee-scrolls** so a long one can be read in full. Tap to open the
  full app.

## Data sources (free, no API keys)

| Data | Source | Notes |
|------|--------|-------|
| Land POIs | [Overpass API](https://overpass-api.de) (OpenStreetMap) | Uses the main EU instance `overpass-api.de`. It intermittently returns a 406 (surfacing as `-400`) on roughly half of requests, so a failed request is simply retried — that overcomes it within a second or two. (Other public mirrors — `kumi.systems`, `private.coffee` — proved unreachable *from the watch* and an unreachable host *hangs* with no fast fail, so they were removed: a dead mirror would freeze the app on "Loading places".) The query uses Overpass `convert` to project only the needed fields → compact `application/json` (CSV would be smaller but the watch rejects `text/csv`). Fetched at most every ~60 s and after moving >400 m. Edit `OVERPASS_MIRRORS` in `source/PoiModel.mc` to change the endpoint. |

Requests go through the **paired phone** (Garmin Connect Mobile must be
running with internet access). Without the phone you'll see error `-104`.

**Attribution:** POI data is from OpenStreetMap — **© OpenStreetMap
contributors** ([ODbL](https://www.openstreetmap.org/copyright)). The credit is
also shown in‑app under Filters → "Map data".

## Project layout

```
manifest.xml            app manifest (watchapp, venux1)
monkey.jungle           build file
resources/              strings, properties, settings UI, launcher icon
scripts/make_icon.py    regenerates the launcher icon (stdlib-only Python)
source/
  AheadApp.mc           app entry point
  PoiModel.mc           GPS, compass, Overpass fetching, state
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
monkeyc -d venux1 -f monkey.jungle -o Ahead.prg -y developer_key.der
```

### 4. Run in the simulator (recommended first)

```sh
connectiq            # starts the simulator
monkeydo Ahead.prg venux1
```

In the simulator use *Simulation → Locations* to set a GPS position
(pick a city center so Overpass returns plenty of POIs).

### 5. Sideload to the watch

Connect the watch over USB (MTP) and copy `Ahead.prg` into the
watch's `GARMIN/Apps` folder. The app appears in the activity/app list.

## Usage

| Input | Action |
|-------|--------|
| **Tap the screen**, or the **Start/Enter button** | Open the **detail page** of the shown POI (scrollable: full description, address, hours, website, …) |
| **Swipe in from the right edge** | Filters menu (settings) — category toggles + "Refresh now" |
| **Swipe down** | Quick "show only one category" — a one-shot (e.g. just restaurants, or just museums) that does **not** change your saved filters; the next normal search reverts to them |
| Swipe up | Nearest-POI list; select an entry opens its detail page. The first row toggles the field-of-view filter, so you can list POIs in **all directions** (including behind you), not just those ahead |
| Long-press screen | Filters menu (only where the firmware emits it) |
| Back | Exit |

On the detail page: swipe up/down (or the buttons) to scroll, **Start** to
lock/unlock the POI as your target, **Back** to return.

On a sideloaded build the phone settings are unavailable, so the **Filters
menu is where you turn POI categories on and off** — open it with the Start
button or a right-edge swipe.

Status line at the bottom: current heading and POI count (or load/error
state).

The launcher icon can be regenerated with `python3 scripts/make_icon.py`.

## Settings

Via Garmin Connect Mobile (or Connect IQ Store app) → Ahead →
Settings: max places and the category toggles. (POIs auto-expand 200 m→5 km
and need no radius setting.) Category toggles changed on the watch are
persisted and synced back.

## CI (GitHub Actions)

`.github/workflows/build.yml` builds the app on every push/PR and uploads
`Ahead.prg` as a workflow artifact (download it from the run page and
sideload it). On `v*` tags it additionally exports the store package
(`Ahead.iq`).

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
| Status shows `retrying...` | A request to overpass-api.de failed transiently (it 406s on ~half of requests, surfacing as -400). The app just retries and it clears within a second or two. |
| Status shows `no phone` | Watch not connected to the phone / no internet (`-104`) — this one needs you to act. |
| `0 POI` everywhere | All categories disabled, or genuinely nothing within 5 km — open Filters (Start button) and enable categories |
| Arrow points the wrong way / compass frozen | Open Filters → **Calibrate compass** and wave the watch in a figure-8 until "N" points north. (The OS auto-calibrates from the motion; Connect IQ can't trigger calibration directly. If it stays wrong, recalibrate in the watch's system Sensors settings.) |

## Adding more devices

Add product ids to `manifest.xml` (e.g. `<iq:product id="venu3"/>`) and
download the matching device files in the SDK Manager. All drawing is
resolution-independent, so round displays work too.

## Sister app

Live aircraft tracking (what plane is that overhead?) used to live here too,
but moved to a dedicated app, **[Planes Above Me](../garmin-planesaboveme)** —
this app is POIs-on-the-ground only.
