import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp, defaultConfig } from './app.js';

const OFFICE = { latitude: defaultConfig.officeLat, longitude: defaultConfig.officeLng };

async function start(now = () => new Date("2026-10-28T04:00:00Z")) {
  const app = createApp({ now });
  await new Promise((r) => app.server.listen(0, r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const call = async (method, path, body, headers = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: { "content-type": "application/json", ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  };
  return { app, call, close: () => app.server.close() };
}

const event = (id, type, extra = {}) => ({
  eventId: id, employeeId: 'EMP-1042', type, timestamp: '2026-10-28T03:30:00Z', ...OFFICE, ...extra,
});

test('core read endpoints return seeded data', async () => {
  const { call, close } = await start();
  const me = (await call('GET', '/employee/me')).body;
  assert.equal(me.id, 'EMP-1042');
  assert.deepEqual(me.office, { latitude: OFFICE.latitude, longitude: OFFICE.longitude, radiusMeters: 200 });
  assert.equal((await call('GET', '/leave/balance')).body.available, 12);
  assert.ok((await call('GET', '/leave/requests')).body.requests.length >= 3);
  const att = await call('GET', '/attendance?month=2026-10');
  assert.equal(att.status, 200);
  assert.ok(att.body.records.every((r) => r.date.startsWith('2026-10')));
  assert.equal((await call('GET', '/attendance?month=bad')).status, 400);
  close();
});

test('event is accepted once and replays original outcome idempotently', async () => {
  const { call, close } = await start();
  const e = event('evt-aaaa-0001', 'check_in');
  const first = await call('POST', '/attendance/events', e, { 'Idempotency-Key': e.eventId });
  assert.equal(first.status, 200);
  assert.equal(first.body.replayed, false);
  const retry = await call('POST', '/attendance/events', e, { 'Idempotency-Key': e.eventId });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.replayed, true);
  close();
});

test('duplicate check-in with a new event id is a 409 conflict', async () => {
  const { call, close } = await start();
  await call('POST', '/attendance/events', event('evt-aaaa-0001', 'check_in'));
  const dup = await call('POST', '/attendance/events', event('evt-aaaa-0002', 'check_in'));
  assert.equal(dup.status, 409);
  assert.equal(dup.body.code, 'DUPLICATE_ATTENDANCE');
  close();
});

test('check-out without check-in is rejected as invalid order', async () => {
  const { call, close } = await start();
  const r = await call('POST', '/attendance/events', event('evt-aaaa-0003', 'check_out'));
  assert.equal(r.status, 409);
  assert.equal(r.body.code, 'INVALID_ORDER');
  close();
});

test('validation and geofence errors are reported', async () => {
  const { call, close } = await start();
  const bad = await call('POST', '/attendance/events', { eventId: 'x' });
  assert.equal(bad.status, 422);
  const far = await call('POST', '/attendance/events', event('evt-aaaa-0004', 'check_in', { latitude: OFFICE.latitude + 0.5284 }));
  assert.equal(far.body.code, 'OUTSIDE_GEOFENCE');
  assert.match(far.body.message, /you were 58\.8 km from the office\. Attendance must be within 200 m/);
  close();
});

test('timeout_after_accept scenario stores the event so a retry is a replay', async () => {
  const { call, close, app } = await start();
  await call('POST', '/__mock/scenario', { name: 'timeout_after_accept', delayMs: 10 });
  const e = event('evt-aaaa-0005', 'check_in');
  await call('POST', '/attendance/events', e);
  const retry = await call('POST', '/attendance/events', e);
  assert.equal(retry.body.replayed, true);
  assert.equal(app.state().attendance.size, 13);
  close();
});

test('server_error scenario fails the next request only', async () => {
  const { call, close } = await start();
  await call('POST', '/__mock/scenario', { name: 'server_error' });
  assert.equal((await call('GET', '/employee/me')).status, 500);
  assert.equal((await call('GET', '/employee/me')).status, 200);
  close();
});

test('leave validation: fields, overlap, balance, and forced rejection', async () => {
  const { call, close } = await start();
  const ok = { type: 'casual', startDate: '2026-11-02', endDate: '2026-11-03', reason: 'Visiting family for a wedding' };
  const bad = await call('POST', '/leave/requests', { ...ok, startDate: '2026-10-01', reason: 'short' });
  assert.equal(bad.status, 422);
  assert.ok(bad.body.errors.startDate && bad.body.errors.reason);
  const tooLong = await call('POST', '/leave/requests', { ...ok, endDate: '2026-12-30' });
  assert.match(tooLong.body.errors.endDate, /available/);

  const created = await call('POST', '/leave/requests', ok);
  assert.equal(created.status, 201);
  assert.equal(created.body.days, 2);
  assert.equal((await call('GET', '/leave/balance')).body.available, 10);
  const overlap = await call('POST', '/leave/requests', { ...ok, startDate: '2026-11-03', endDate: '2026-11-04' });
  assert.match(overlap.body.errors.startDate, /Overlaps/);

  await call('POST', '/__mock/scenario', { name: 'leave_reject' });
  const forced = await call('POST', '/leave/requests', { ...ok, startDate: '2026-11-20', endDate: '2026-11-20' });
  assert.equal(forced.status, 422);
  close();
});

test('dev controls are disabled in production mode', async () => {
  const app = createApp({ config: { devControls: false } });
  await new Promise((r) => app.server.listen(0, r));
  const res = await fetch(`http://127.0.0.1:${app.server.address().port}/__mock/state`);
  assert.equal(res.status, 404);
  app.server.close();
});

test("dev office control moves the geofence", async () => {
  const { call, close } = await start();
  const far = { latitude: OFFICE.latitude + 0.5284, longitude: OFFICE.longitude };
  assert.equal(
    (
      await call(
        "POST",
        "/attendance/events",
        event("evt-aaaa-0020", "check_in", far),
      )
    ).body.code,
    "OUTSIDE_GEOFENCE",
  );
  assert.equal((await call("POST", "/__mock/office", far)).status, 200);
  assert.equal(
    (
      await call(
        "POST",
        "/attendance/events",
        event("evt-aaaa-0021", "check_in", far),
      )
    ).status,
    200,
  );
  assert.equal(
    (await call("POST", "/__mock/office", { latitude: "x" })).status,
    400,
  );
  close();
});

test('invalid-order outcomes are not cached, so a retry after the check-in succeeds', async () => {
  const { call, close } = await start();
  const out = await call('POST', '/attendance/events', event('evt-aaaa-0030', 'check_out'));
  assert.equal(out.body.code, 'INVALID_ORDER');
  assert.equal((await call('POST', '/attendance/events', event('evt-aaaa-0031', 'check_in'))).status, 200);
  assert.equal((await call('POST', '/attendance/events', event('evt-aaaa-0030', 'check_out'))).status, 200);
  close();
});

test('leave requests are idempotent on requestId', async () => {
  const { call, close } = await start();
  const body = { requestId: 'req-1', type: 'casual', startDate: '2026-12-10', endDate: '2026-12-11', reason: 'Family function' };
  const first = await call('POST', '/leave/requests', body);
  const again = await call('POST', '/leave/requests', body);
  assert.equal(first.status, 201);
  assert.equal(again.body.id, first.body.id);
  assert.equal((await call('GET', '/leave/balance')).body.available, 10);
  close();
});
