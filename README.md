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
- **Categories** (toggle on the watch via hold-menu, or in phone settings):
  - Historic & sights — OSM `historic=*`, attractions, viewpoints
  - Food & drink — restaurants, cafés, bars, pubs, fast food
  - Culture — museums, galleries, theatres, cinemas, churches, libraries
  - Aircraft (live) — overhead air traffic with callsign, altitude, speed
    and ground track
- Search radius configurable 0.5–10 km (default 5 km).

## Data sources (free, no API keys)

| Data | Source | Notes |
|------|--------|-------|
| Land POIs | [Overpass API](https://overpass-api.de) (OpenStreetMap) | Public servers, fair-use. The app fetches at most every 60 s and only after you move >400 m. It rotates across several mirrors (`overpass-api.de`, `overpass.osm.ch`, `kumi.systems`, `private.coffee`) and retries on the next one if a request fails — the main instance intermittently returns a 406 page that can't be parsed. |
| Aircraft | [OpenSky Network](https://opensky-network.org) | Anonymous access has a daily request budget (~400 credits/day, 1–4 per call). Default refresh is 30 s; raise it in settings if you watch planes for hours. |

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
| Tap screen / select key / swipe up | Nearest-POI list; select = lock target |
| Hold for menu | Category filters + "Refresh now" |
| Back | Exit |

Status line at the bottom: current heading, POI count (or load/error
state), aircraft count when the aircraft category is enabled.

The launcher icon can be regenerated with `python3 scripts/make_icon.py`.

## Settings

Via Garmin Connect Mobile (or Connect IQ Store app) → POI Finder →
Settings: search radius, max places, category toggles, aircraft refresh
interval. Category toggles changed on the watch are persisted and synced
back.

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
| `POI err -400` | A mirror returned a non-JSON page (e.g. overpass-api.de's intermittent 406). The app rotates to another mirror and retries within ~8 s; transient. |
| `POI err 429` / `504` | Overpass server busy — rotates to another mirror and retries (~8 s) |
| `air err 429` | OpenSky anonymous daily budget exhausted |
| `POI err -402` | Response too large — reduce radius or max places |
| Compass frozen | Calibrate compass (figure-8 motion); Venu X1 has a magnetometer |

## Adding more devices

Add product ids to `manifest.xml` (e.g. `<iq:product id="venu3"/>`) and
download the matching device files in the SDK Manager. All drawing is
resolution-independent, so round displays work too.
