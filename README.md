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

  Defaults on: Monuments, Castles, Ruins, Viewpoints, Restaurants, Museums.
- **Field of view** — POIs are shown only when they're roughly in front
  of you (within ~45° of your heading, ~90° total). As you turn, the set
  re-filters live from the already-loaded data (no refetch), with hysteresis so
  POIs near the edge don't flicker.
- **Range** — an *expanding search* that widens only until something is found
  (up to 5 km). The starting radius tracks GPS precision: **50 m** on a good
  fix, ~200 m on a usable one, ~500 m while the position is still approximate —
  so a precise fix in a city shows exactly what's right in front of you. The
  query uses Overpass `convert` to return only the fields it needs, keeping the
  response small enough to parse on-watch.
- **Fast start** — on launch the app seeds from the cached last-known position
  so POIs load immediately while the GPS warms up. The status line shows a
  leading `~` until a precise fix arrives, then the list is refined to it.

## Data sources (free, no API keys)

| Data | Source | Notes |
|------|--------|-------|
| Land POIs | [Overpass API](https://overpass-api.de) (OpenStreetMap) | Tries `maps.mail.ru` first (it answered 100% reliably in testing), failing over to `overpass-api.de` (whose public instance 406s ~half its requests, so it's only a fallback). **Note:** mail.ru is Russian infrastructure and receives your search coordinates — reorder `OVERPASS_MIRRORS` in `source/PoiModel.mc` (e.g. put `overpass-api.de` or a self-hosted instance first) if you'd rather not use it. The query uses Overpass `convert` to project only the needed fields → compact `application/json` (CSV would be smaller but the watch rejects `text/csv`). Fetched at most every ~60 s and after moving >400 m. |

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
| **Tap the screen**, or the **Start/Enter button** | Open the **detail page** of the shown POI (scrollable: full description, address, hours, website, …) |
| **Swipe in from the right edge** | Filters menu (settings) — category toggles + "Refresh now" |
| **Swipe down** | Quick "show only one category" — a one-shot (e.g. just restaurants, or just museums) that does **not** change your saved filters; the next normal search reverts to them |
| Swipe up | Nearest-POI list; select an entry opens its detail page |
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

Via Garmin Connect Mobile (or Connect IQ Store app) → POI Finder →
Settings: max places and the category toggles. (POIs auto-expand 200 m→5 km
and need no radius setting.) Category toggles changed on the watch are
persisted and synced back.

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
| `POI err 406` / `-400` / `504` / `429` | A mirror failed (overpass-api.de 406s a lot, which surfaces as -400). The app fails over to the next mirror and retries; usually transient. |
| `0 POI` everywhere | All categories disabled, or genuinely nothing within 5 km — open Filters (Start button) and enable categories |
| Compass frozen | Calibrate compass (figure-8 motion); Venu X1 has a magnetometer |

## Adding more devices

Add product ids to `manifest.xml` (e.g. `<iq:product id="venu3"/>`) and
download the matching device files in the SDK Manager. All drawing is
resolution-independent, so round displays work too.

## Sister app

Live aircraft tracking (what plane is that overhead?) used to live here too,
but moved to a dedicated app, **[Planes Above Me](../garmin-planesaboveme)** —
this app is POIs-on-the-ground only.
