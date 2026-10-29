# REBS HRMS – Employee Workspace

A Flutter app for a single preconfigured employee (`EMP-1042`). It provides a dashboard, GPS-validated attendance with an
offline-first sync queue, and leave applications. A dependency-free Node.js mock API backs the app.

## Table of contents

- [Features](#features)
- [Project structure](#project-structure)
- [Architecture](#architecture)
- [Getting started](#getting-started)
- [Running, testing and building](#running-testing-and-building)
- [Simulating GPS](#simulating-gps)
- [Mock API](#mock-api)
- [Offline behaviour and recovery](#offline-behaviour-and-recovery)
- [Offline queue and sync design](#offline-queue-and-sync-design)
- [Production server requirements](#production-server-requirements)
- [Scope, assumptions and limitations](#scope-assumptions-and-limitations)
- [Demo walkthrough](#demo-walkthrough)

## Features

- **Dashboard** – profile, company date, attendance status, check-in/out times, live elapsed timer, leave balance, the
  latest five records, and sync/offline state.
- **Attendance** – check in and out with GPS validation against the office geofence (200 m radius by default).
- **Leave** – balance, request list with statuses, and an application form with local and server-side validation.
- **Offline-first** – attendance events and leave requests are stored in a durable local queue and sent when the server
  is reachable. Profile, balance, history and leave data are cached.
- **Mock API** – in-memory server with injectable failure scenarios for testing slow, failing and duplicate responses.

## Project structure

```
lib/
  app/             App shell; lifecycle- and connectivity-triggered sync
  core/            Config, design tokens/theme/widgets, errors, company-timezone clock
  domain/          Models, attendance rules + haversine distance, leave rules (pure Dart)
  data/
    local/         SQLite schema, attendance store (events + merged days), leave outbox, cache store
    remote/        HrmsApi (Dio) and delivery-outcome classification
    sync/          SyncService (ordered, single-flight, backoff)
    location/      Device GPS, simulated location and debug location override
    repositories/  AttendanceService (rules + GPS + locking), LeaveRepository, WorkspaceRepository
  features/        dashboard / attendance / leave – Bloc cubits and screens
mock_api/          Node HTTP server and node:test suite
test/              Unit tests, widget tests and shared fakes
tool/e2e_check.dart  Manual check of the real client against a live server
```

## Architecture

The app is feature-first and layered:

- `domain` is pure Dart with no Flutter or I/O dependencies.
- `data` owns SQLite and HTTP.
- `features/*/presentation` holds the controllers and screens.

**State management** is `flutter_bloc` (cubits only). `main.dart` wires repositories by hand and exposes them through
`RepositoryProvider` / `BlocProvider`; tests substitute fake cubits.

**Storage** is `sqflite` for structured data and the event queue (not `shared_preferences`). **Networking** uses `Dio`.

Office coordinates, radius and company timezone are compile-time configuration (`AppConfig`); the mock server mirrors
the same defaults.

## Getting started

### Prerequisites

- Flutter 3.47+ and Dart 3.13+
- Node.js 20+ (tested with Node 26)
- For Android builds: JDK 17+ and the Android SDK with accepted licences

### Install and start

```bash
flutter pub get
cd mock_api && npm start        # serves http://0.0.0.0:3000
```

The mock API has no runtime dependencies, so `npm install` is not required.

### API base URL per target

| Target | Value |
|---|---|
| Android emulator | `http://10.0.2.2:3000` (default; the emulator's alias for the host) |
| iOS simulator | `http://localhost:3000` (default) |
| Physical device | `--dart-define=API_BASE_URL=http://<computer-LAN-IP>:3000` (device and computer on the same Wi-Fi) |

Debug builds allow cleartext HTTP (`android/app/src/debug`), and iOS uses `NSAllowsLocalNetworking`. Release builds do
not allow plain HTTP.

## Running, testing and building

```bash
# Run the app (see "Simulating GPS")
flutter run --dart-define=SIMULATED_LOCATION=inside

# Format, analyse and run the app tests
dart format . && flutter analyze && flutter test

# Run the mock API tests
(cd mock_api && npm test)

# Build a debug APK -> build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --debug

# Run the real client against a live mock server
dart run tool/e2e_check.dart http://localhost:3000
```

## Simulating GPS

Pass `--dart-define=SIMULATED_LOCATION=<value>`. This is honoured **in debug builds only**.

| Value | Meaning |
|---|---|
| `inside` | Exactly at the office (9.9828967, 76.28197009) |
| `outside` | About 1.1 km north, so attendance is refused with the measured distance |
| `9.9830,76.2820` | Any `lat,lng` |

### Test location button (debug builds only)

The Home app bar has a **Test location** button with two modes:

- **Your location** – pretend the device is at any latitude/longitude.
- **Office** – move the office to any latitude/longitude. The app also notifies the running mock server
  (`POST /__mock/office`) so the server-side geofence agrees. If the server is unreachable, the app reports that only
  the app was updated.

Both modes offer **Use current location**, which fills the fields from the device's real GPS (with the usual permission
and disabled-services handling). Settings survive restarts; **Reset** returns to real GPS and the configured office.
To pass the check from anywhere, set the office to the same coordinates as your location.

Distances are shown in metres below 1 km and in km above (for example, `33.3 km`).

### Real GPS and custom office

Without a simulated location, the real GPS is used. Permission prompts, disabled location services, permanently denied
permission (with a shortcut to settings), timeouts and unavailable fixes each show a specific message.

Override the office with dart-defines:

```bash
--dart-define=OFFICE_LAT=… --dart-define=OFFICE_LNG=… --dart-define=COMPANY_TZ=Europe/London
```

Start the mock server with matching `OFFICE_LAT`, `OFFICE_LNG`, `OFFICE_RADIUS_M` and `COMPANY_TZ` environment
variables.

## Mock API

State is held in memory and seeded relative to today. Restarting the server, or calling `POST /__mock/reset`, restores
it.

| Endpoint | Notes |
|---|---|
| `GET /employee/me` | Employee id, name, department, and the office location/radius |
| `GET /attendance?month=YYYY-MM` | `{records: [{date, checkIn, checkOut}]}` |
| `POST /attendance/events` | Body: `{eventId, employeeId, type, timestamp, latitude, longitude}` plus an `Idempotency-Key` header. Returns **200** accepted, **409** `DUPLICATE_ATTENDANCE` / `INVALID_ORDER`, or **422** validation / `OUTSIDE_GEOFENCE`. A replayed `eventId` returns the original outcome with `replayed: true` |
| `GET /leave/balance` | `{available}` |
| `GET` / `POST /leave/requests` | Validation failures return 422 `{message, errors: {field: msg}}`. Creating a request reserves its days from the balance. POST is idempotent on `requestId` |

### Failure scenarios (development only)

Scenarios are disabled when `NODE_ENV=production` (`/__mock/*` then returns 404). Each one applies to the next `count`
matching requests.

```bash
curl -X POST localhost:3000/__mock/scenario \
  -H 'content-type: application/json' \
  -d '{"name":"timeout_after_accept"}'
```

| Name | Effect |
|---|---|
| `slow` | Delays the next request by `delayMs` (default 8000; the client timeout is 5–6 s) |
| `server_error` | Next request returns 500 |
| `timeout_after_accept` | The event **is committed**, but the response is delayed past the client timeout; the retry gets `replayed: true` |
| `duplicate` | Next attendance event returns 409 `DUPLICATE_ATTENDANCE` |
| `invalid_order` | Next attendance event returns 409 `INVALID_ORDER` |
| `leave_reject` | Next leave POST returns 422 with a field error that passed local validation |

Other control endpoints:

- `DELETE /__mock/scenario` – clear scenarios
- `POST /__mock/reset` – re-seed state
- `GET /__mock/state` – inspect state
- `MOCK_SCENARIO=server_error:3 npm start` – start with a scenario preloaded

To trigger natural invalid ordering: stop the mock mid-day, check in offline, reset the server, then sync. The
check-out is refused because the check-in no longer exists on the server.

## Offline behaviour and recovery

- **Office config.** The server publishes the office (`office.latitude/longitude/radiusMeters`) in `GET /employee/me`.
  The app caches it and checks distance against it, so app and server cannot disagree. Before the first successful
  fetch it uses the `OFFICE_LAT` / `OFFICE_LNG` defaults, which match the mock server's.
- **Server down.** The app keeps working from its cache, shows an Offline banner, and stores attendance locally.
- **Automatic recovery.** Every 20 seconds, while offline, errored or holding pending actions, the app probes the
  server. As soon as it answers, data refreshes and pending actions are sent (backoff is skipped because reachability
  was just proven). **Sync now** does the same on demand.
- **The server is the source of truth.** After every successful fetch the app compares its events with the server's
  attendance:
  - Anything this device marked *Synced* that the server does not have goes back to *Pending* with the same event id.
  - A check-out refused only because its check-in was missing is queued again behind that check-in.
  - A check-out refused as "invalid order" while a local check-in exists waits instead of being rejected.
  - Server data for days the device does not know about replaces the cached history.
- **Leave applications** are also offline-first. They are validated locally, saved in a durable queue (shown as
  *Pending Sync*, with days reserved from the balance), and sent with a stable `requestId` once the server is
  reachable. A server refusal is kept as *Rejected* with its reason until dismissed; accepted requests then appear from
  the server list.
- **Server restarts.** The mock server keeps state in memory, so restarting it forgets earlier check-ins. The
  reconciliation above re-sends them automatically.
- **Clearing rejections.** **Clear rejected** on the Attendance tab removes stale rejections. Pending actions are never
  removed.

## Offline queue and sync design

1. `AttendanceService.record` (under an async lock) checks the rules, asks for GPS, checks the 200 m radius, and inserts
   the event in a SQLite transaction with status `pending`. Only then is delivery attempted. The UI shows the event
   immediately from the local database.
2. Rules are re-checked inside the insert transaction against server history **plus** local events. A partial unique
   index `(employee, work_date, type) WHERE status != 'rejected'` backs them up at the database level.
3. `SyncService` sends pending events ordered by timestamp. It is single-flight (concurrent callers share one run), so
   no event is submitted twice at once. A transient failure stops the run, so a check-out is never sent before its
   check-in.
4. Sync triggers: after each local action, pull-to-refresh, **Sync now** (ignores backoff), connectivity returning, app
   resume, and a 20-second timer that retries events whose backoff has elapsed. Nothing runs after the app is killed.
5. Backoff is `min(300 s, 2^(n+1) s)`. Automatic retries stop after 8 attempts (manual sync still works). Events are
   never deleted.

### Identity, idempotency and timeouts

The event UUID is generated once at creation and sent as both `eventId` and `Idempotency-Key` on every retry.

| Outcome | Result |
|---|---|
| Accepted (including `replayed: true`) | `synced` |
| Definitive 4xx (409, 422, 400, …) | `rejected`, with the server's reason shown on the event and the day. A rejected event stops counting, so the employee can try again |
| Timeout, connection error, 5xx, 401/403/408/429 | Stays `pending` with the error and attempt count |

A send/receive timeout is marked *uncertain* ("the server may have received it"). The retry reuses the same ID and the
server answers with the original outcome, so a committed event reconciles as synced and is never duplicated or wrongly
rejected.

The local view is server history overlaid with non-rejected local events, so a refresh that races a local action cannot
hide it.

## Production server requirements

Device-side GPS and attendance checks are **not a security boundary**: location can be spoofed, the clock changed and
the client modified. A real backend must:

- authenticate and authorise the employee;
- enforce event-id uniqueness and idempotent replay;
- validate timestamps (bounds, skew, company-day derivation);
- apply the geofence/location policy (and consider mock-location signals);
- enforce attendance transitions per day;
- rate-limit requests.

The mock API demonstrates these server-side checks but is not production code.

## Scope, assumptions and limitations

**Assumptions**

- One employee (`EMP-1042`) and fixed configuration via dart-define.
- The leave balance is a single number, every calendar day counts, and the server reserves days at submission.
- A day is one check-in / check-out pair.

**Limitations**

- No authentication.
- No background sync after the app is terminated; the 20-second retry timer runs only while the app is open.
- `sqflite` runs on Android and iOS only. Tests use `sqflite_common_ffi` and need `libsqlite3` on the host.
- Mock server state is in memory.
- The UI has not been exercised on a physical device in every environment.

## Demo walkthrough

A 3–5 minute demo:

1. Run `cd mock_api && npm start`, then `flutter run --dart-define=SIMULATED_LOCATION=outside`. The dashboard loads and
   check-in is refused with the distance.
2. Restart with `inside`. Check-in works, the elapsed timer runs, and the event shows as *Synced* in the Attendance tab.
3. Stop the mock server and check out. It shows *Pending Sync* and the Offline banner. Kill and reopen the app; it is
   still pending.
4. Start the server with a `timeout_after_accept` scenario and tap **Sync now**. The event stays pending ("server may
   have received it"). Sync again and it becomes *Synced*, with no duplicate.
5. Apply `duplicate` before a check-in on a fresh day (or reset the server) to show a *Rejected* event with its reason.
6. Leave: review the balance and requests, then apply with invalid inputs (inline errors), an overlap, and an
   over-balance request. Use `leave_reject` to show a server field error. Go offline and apply anyway (it appears as
   *Pending Sync* and reserves the days), then bring the server back and watch it sync.
