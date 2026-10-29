# REBS HRMS: Employee Workspace

Flutter app for one preconfigured employee (EMP-1042): dashboard, GPS-validated attendance with an offline-first
sync queue, and leave applications. A dependency-free Node mock API backs it.

```
lib/
  app/            app shell, lifecycle/connectivity-triggered sync
  core/           config, design tokens/theme/widgets, errors, company-timezone clock
  domain/         models, attendance rules + haversine, leave rules (pure Dart)
  data/
    local/        SQLite schema, attendance store (events + merged days), cache store
    remote/       HrmsApi (Dio) and delivery-outcome classification
    sync/         SyncService (ordered, single-flight, backoff)
    location/     device GPS + deterministic simulated location
    repositories/ AttendanceService (rules + GPS + locking), LeaveRepository, WorkspaceRepository
  features/       dashboard / attendance / leave: Bloc cubits + screens
mock_api/         Node http server + node:test suite
test/             unit, widget tests and shared fakes
tool/e2e_check.dart   manual client-vs-live-server check
```

## Architecture and state management

Feature-first, layered: `domain` is pure Dart, `data` owns SQLite/HTTP, `features/*/presentation` holds controllers and
screens. **Bloc** (`flutter_bloc`, cubits only) is the only state management: `main.dart` wires repositories by hand and provides them via
`RepositoryProvider`/`BlocProvider`; tests supply fake cubits. **sqflite** stores structured data and the event queue (not shared_preferences). **Dio** does HTTP.
Office coordinates, radius and company timezone are compile-time config (`AppConfig`); the mock server mirrors them.

## Prerequisites and setup

- Flutter 3.47+ / Dart 3.13+, Node 20+ (tested with Node 26). No npm install is needed; the mock API has no dependencies.
- Android builds need a JDK 17+ and the Android SDK with accepted licences.

```bash
flutter pub get
cd mock_api && npm start          # http://0.0.0.0:3000
```

### API base URL per target

| Target | Value |
|---|---|
| Android emulator | default `http://10.0.2.2:3000` (emulator alias for the host) |
| iOS simulator | default `http://localhost:3000` |
| Physical device | `--dart-define=API_BASE_URL=http://<computer-LAN-IP>:3000` (same Wi-Fi) |

Debug builds allow cleartext HTTP (`android/app/src/debug`); iOS uses `NSAllowsLocalNetworking`. Release builds
do not allow plain HTTP.

## Run, test, build

```bash
flutter run --dart-define=SIMULATED_LOCATION=inside      # see GPS section
dart format . && flutter analyze && flutter test         # app tests
(cd mock_api && npm test)                                # API tests
flutter build apk --debug                                # build/app/outputs/flutter-apk/app-debug.apk
dart run tool/e2e_check.dart http://localhost:3000       # real client against a live mock server
```

## Simulating GPS

`--dart-define=SIMULATED_LOCATION=<value>`, honoured **in debug builds only**:

- `inside`: exactly the office (12.9716, 77.5946).
- `outside`: ~1.1 km north, so attendance is refused with the measured distance.
- `12.9720,77.5950`: any `lat,lng`.

Without it the real GPS is used (permission prompt, disabled services, denied-forever with a settings shortcut,
timeout and unavailable fix are all handled with specific messages). Override the office with
`--dart-define=OFFICE_LAT=… --dart-define=OFFICE_LNG=…` and `COMPANY_TZ=Europe/London`; start the mock with
`OFFICE_LAT/OFFICE_LNG/OFFICE_RADIUS_M/COMPANY_TZ` env vars to match.

## Mock API

In-memory state, seeded relative to today; restarting (or `POST /__mock/reset`) restores it.

| Endpoint | Notes |
|---|---|
| `GET /employee/me` | id, name, department |
| `GET /attendance?month=YYYY-MM` | `{records:[{date, checkIn, checkOut}]}` |
| `POST /attendance/events` | `{eventId, employeeId, type, timestamp, latitude, longitude}` + `Idempotency-Key` header. 200 accepted · 409 `DUPLICATE_ATTENDANCE` / `INVALID_ORDER` · 422 validation, `OUTSIDE_GEOFENCE`. Replays of an `eventId` return the original outcome (`replayed: true`) |
| `GET /leave/balance` | `{available}` |
| `GET/POST /leave/requests` | 422 `{message, errors:{field:msg}}`; creating a request reserves its days from the balance |

### Failure scenarios (dev only)

Disabled when `NODE_ENV=production` (`/__mock/*` returns 404). Each applies to the next `count` matching requests.

```bash
curl -X POST localhost:3000/__mock/scenario -H 'content-type: application/json' -d '{"name":"timeout_after_accept"}'
```

| name | effect |
|---|---|
| `slow` | delays the next request by `delayMs` (default 8000, client timeout is 5–6 s) |
| `server_error` | next request → 500 |
| `timeout_after_accept` | event **is committed** but the response is delayed past the client timeout; the retry gets `replayed: true` |
| `duplicate` | next attendance event → 409 `DUPLICATE_ATTENDANCE` |
| `invalid_order` | next attendance event → 409 `INVALID_ORDER` |
| `leave_reject` | next leave POST → 422 with a field error that passed local validation |

Also: `DELETE /__mock/scenario` clears, `POST /__mock/reset` re-seeds, `GET /__mock/state`, or start with
`MOCK_SCENARIO=server_error:3 npm start`. Natural invalid ordering: stop the mock mid-day, check in offline,
reset the server, and the check-out is refused on sync.

## Offline queue and sync design

1. `AttendanceService.record` (under an async lock) checks rules → asks for GPS → checks the 200 m radius → inserts
   the event in a SQLite transaction with status `pending`. Only then is delivery attempted. The UI shows it
   immediately from the local DB.
2. Rules are re-checked inside the insert transaction against server history **plus** local events, and a partial
   unique index `(employee, work_date, type) WHERE status != 'rejected'` backs them up at the database level.
3. `SyncService` sends pending events ordered by timestamp. It is single-flight (concurrent callers share one run),
   so no event is submitted twice at once. A transient failure stops the run, so a check-out is never sent before its check-in.
4. Triggers: after each local action, pull-to-refresh, **Sync now** (ignores backoff), connectivity returning,
   app resume, and a 20 s timer that retries events whose backoff elapsed. Nothing runs after the app is killed (out of scope).
5. Backoff is `min(300 s, 2^(n+1) s)`; automatic retries stop after 8 attempts (manual Sync still works). Events are never deleted.

### Identity, idempotency, timeouts

The event UUID is generated once at creation and sent as both `eventId` and `Idempotency-Key` on every retry. Outcomes:

- **Accepted** (including `replayed: true`): `synced`.
- **Definitive 4xx** (409/422/400…): `rejected`, with the server's reason shown on the event and the day.
  A rejected event stops counting, so the employee can try again.
- **Timeout, connection error, 5xx, 401/403/408/429**: stays `pending` with the error and attempt count.
  A send/receive timeout is marked *uncertain* ("the server may have received it"). The retry reuses the same ID, and the server
  answers with the original outcome, so a committed event reconciles as synced and is never duplicated or wrongly rejected.

The local view is server history overlaid with non-rejected local events, so a refresh that raced a local action cannot hide it.

## Production server validation

Device-side GPS and attendance checks are **not a security boundary**: location can be spoofed, the clock changed and the
client modified. A real backend must independently authenticate and authorise the employee; enforce event-ID uniqueness
and idempotent replay; validate timestamps (bounds, skew, company-day derivation); apply the geofence/location policy
(and consider mock-location signals); enforce attendance transitions per day; and rate-limit. The mock API demonstrates
those server-side checks but is not production code.

## Completed, assumptions, limitations

Completed: dashboard (profile, company date, status, times, live elapsed timer, balance, latest five, sync/offline state), GPS
attendance, durable queue with sync summary and Sync Now, leave form with local + server validation and request list, mock
API with scenarios, offline cache for profile/balance/history/leave.

Assumptions: one employee (`EMP-1042`), fixed config via dart-define, leave balance is a single number, every calendar day
counts, the server reserves days at submission, and a day is one check-in/check-out pair.

Limitations: no auth; no background sync after termination; sqflite is SQLite on Android/iOS only; tests use
`sqflite_common_ffi` and need `libsqlite3` on the host; mock state is in memory; the 20 s retry timer runs only while the app
is open; the UI has not been exercised on a physical device or emulator in this environment (see the verification notes
delivered with this work). The Gradle build here needed an isolated `GRADLE_USER_HOME` because the shared one was corrupt.

Time spent: built in a single automated session; wall-clock time was not tracked.

## 3–5 minute demo checklist

1. `cd mock_api && npm start`; `flutter run --dart-define=SIMULATED_LOCATION=outside`. Dashboard loads; Check in is refused with the distance.
2. Restart with `inside`: Check in works, the elapsed timer runs, and the event is "Synced" in the Attendance tab.
3. Stop the mock server: check out. It shows **Pending Sync** and the offline banner. Kill and reopen the app: still pending.
4. Start the server with a `timeout_after_accept` scenario: **Sync now** → pending ("server may have received it"); sync again → Synced, no duplicate.
5. Apply `duplicate` before a check-in on a fresh day (or reset) to show a **Rejected** event with its reason.
6. Leave: balance, requests with statuses, Apply with invalid inputs (inline errors), overlap, over-balance, then `leave_reject` for a server field error; go offline to see cached data and the offline error on submit.
