import http from 'node:http';

const EMPLOYEE = { id: 'EMP-1042', name: 'Priya Nair', department: 'Product Engineering' };

export const defaultConfig = {
  timezone: process.env.COMPANY_TZ ?? "Asia/Kolkata",
  officeLat: Number(process.env.OFFICE_LAT ?? 12.9716),
  officeLng: Number(process.env.OFFICE_LNG ?? 77.5946),
  radiusMeters: Number(process.env.OFFICE_RADIUS_M ?? 200),
  devControls: process.env.NODE_ENV !== "production",
};

const formatDistance = (m) =>
  Math.round(m) < 1000 ? `${Math.round(m)} m` : `${(m / 1000).toFixed(1)} km`;

const prettyDate = (s) =>
  new Intl.DateTimeFormat("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(`${s}T00:00:00Z`));

const pad = (n) => String(n).padStart(2, '0');

function companyDate(date, tz) {
  const p = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
  return p;
}

function tzOffsetMs(date, tz) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    }).formatToParts(date).map((p) => [p.type, p.value]),
  );
  const asUtc = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
  return asUtc - Math.floor(date.getTime() / 1000) * 1000;
}

function localToUtc(dateStr, hh, mm, tz) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const guess = new Date(Date.UTC(y, m - 1, d, hh, mm));
  return new Date(guess.getTime() - tzOffsetMs(guess, tz));
}

export function distanceMeters(lat1, lon1, lat2, lon2) {
  const r = 6371000;
  const rad = (d) => (d * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(a));
}

const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));
const dayCount = (a, b) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000) + 1;
const addDays = (s, n) => new Date(Date.parse(`${s}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);

function seed(now, cfg) {
  const today = companyDate(now, cfg.timezone);
  const attendance = new Map();
  let created = 0;
  for (let back = 1; created < 12 && back < 40; back++) {
    const date = addDays(today, -back);
    const dow = new Date(`${date}T00:00:00Z`).getUTCDay();
    if (dow === 0 || dow === 6) continue;
    const inMin = (back * 7) % 25;
    const outMin = (back * 11) % 40;
    attendance.set(date, {
      checkIn: localToUtc(date, 9, 2 + inMin, cfg.timezone).toISOString(),
      checkOut: localToUtc(date, 18, outMin, cfg.timezone).toISOString(),
    });
    created++;
  }
  const leave = [
    { id: 'LV-1', type: 'casual', startDate: addDays(today, -30), endDate: addDays(today, -29), reason: 'Family function out of town', status: 'approved' },
    { id: 'LV-2', type: 'sick', startDate: addDays(today, 14), endDate: addDays(today, 15), reason: 'Scheduled dental procedure', status: 'pending' },
    { id: 'LV-3', type: 'casual', startDate: addDays(today, -60), endDate: addDays(today, -60), reason: 'Personal errand, declined due to release', status: 'rejected' },
  ].map((r) => ({ ...r, days: dayCount(r.startDate, r.endDate) }));
  return {
    attendance,
    events: new Map(),
    leave,
    balance: 12,
    scenarios: [],
    leaveByRequestId: new Map(),
  };
}

export function createApp({ now = () => new Date(), config = {} } = {}) {
  const cfg = { ...defaultConfig, ...config };
  let state = seed(now(), cfg);
  let leaveSeq = 100;

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function takeScenario(...names) {
    const s = state.scenarios.find((x) => names.includes(x.name) && x.remaining > 0);
    if (!s) return null;
    s.remaining--;
    return s;
  }

  function addScenario({ name, count = 1, delayMs = 8000 }) {
    const known = ['server_error', 'slow', 'timeout_after_accept', 'duplicate', 'invalid_order', 'leave_reject'];
    if (!known.includes(name)) return { error: `Unknown scenario. Use one of: ${known.join(', ')}` };
    state.scenarios.push({ name, remaining: count, delayMs });
    return { ok: true };
  }

  const envScenario = process.env.MOCK_SCENARIO;
  if (envScenario && cfg.devControls) {
    const [name, count] = envScenario.split(':');
    addScenario({ name, count: Number(count ?? 1) });
  }

  function processEvent(body) {
    const errors = {};
    if (typeof body.eventId !== 'string' || body.eventId.length < 8) errors.eventId = 'eventId is required';
    if (!['check_in', 'check_out'].includes(body.type)) errors.type = 'type must be check_in or check_out';
    if (typeof body.timestamp !== 'string' || Number.isNaN(Date.parse(body.timestamp))) errors.timestamp = 'timestamp must be ISO-8601';
    if (typeof body.latitude !== 'number' || typeof body.longitude !== 'number') errors.location = 'latitude and longitude are required';
    if (body.employeeId !== EMPLOYEE.id) errors.employeeId = 'Unknown employee';
    if (Object.keys(errors).length) {
      return { code: 422, body: { status: 'rejected', code: 'VALIDATION_ERROR', message: 'Invalid attendance event', errors } };
    }
    const reject = (code, errCode, message) => ({ code, body: { status: 'rejected', code: errCode, message } });
    const ts = new Date(body.timestamp);
    if (ts.getTime() > now().getTime() + 5 * 60000) return reject(422, 'INVALID_TIMESTAMP', 'Event timestamp is in the future');
    const dist = distanceMeters(body.latitude, body.longitude, cfg.officeLat, cfg.officeLng);
    if (dist > cfg.radiusMeters) {
      return reject(
        422,
        "OUTSIDE_GEOFENCE",
        `Outside the office area: you were ${formatDistance(dist)} from the office. Attendance must be within ${formatDistance(cfg.radiusMeters)}.`,
      );
    }
    const date = companyDate(ts, cfg.timezone);
    const day = state.attendance.get(date);
    if (body.type === 'check_in') {
      if (day)
        return reject(
          409,
          "DUPLICATE_ATTENDANCE",
          `You already checked in on ${prettyDate(date)}.`,
        );
      state.attendance.set(date, { checkIn: ts.toISOString(), checkOut: null });
    } else {
      if (!day)
        return reject(
          409,
          "INVALID_ORDER",
          `You need to check in on ${prettyDate(date)} before checking out.`,
        );
      if (day.checkOut)
        return reject(
          409,
          "DUPLICATE_ATTENDANCE",
          `You already checked out on ${prettyDate(date)}.`,
        );
      day.checkOut = ts.toISOString();
    }
    return { code: 200, body: { status: 'accepted', eventId: body.eventId, replayed: false } };
  }

  async function postEvent(req, body, res) {
    const key = req.headers['idempotency-key'];
    if (key && key !== body.eventId) {
      return send(res, 422, { status: 'rejected', code: 'VALIDATION_ERROR', message: 'Idempotency-Key must equal eventId' });
    }
    const seen = state.events.get(body.eventId);
    if (seen) return send(res, seen.code, { ...seen.body, replayed: seen.code === 200 ? true : undefined });

    const forced = takeScenario('duplicate', 'invalid_order');
    if (forced) {
      const code = forced.name === 'duplicate' ? 'DUPLICATE_ATTENDANCE' : 'INVALID_ORDER';
      const out = { code: 409, body: { status: 'rejected', code, message: `Simulated ${code}` } };
      if (code !== "INVALID_ORDER") state.events.set(body.eventId, out);
      return send(res, out.code, out.body);
    }
    const out = processEvent(body);
    if (out.body.code !== "INVALID_ORDER") state.events.set(body.eventId, out);
    const late = takeScenario('timeout_after_accept');
    if (late) await sleep(late.delayMs);
    send(res, out.code, out.body);
  }

  function postLeave(body, res) {
    const replay =
      typeof body.requestId === "string" &&
      state.leaveByRequestId.get(body.requestId);
    if (replay) return send(res, 201, replay);
    if (takeScenario('leave_reject')) {
      return send(res, 422, {
        message: 'Request rejected by server policy',
        errors: { startDate: 'Leave cannot be taken during the quarterly release freeze' },
      });
    }
    const errors = {};
    const today = companyDate(now(), cfg.timezone);
    if (!['casual', 'sick'].includes(body.type)) errors.type = 'Leave type must be casual or sick';
    if (!isDate(body.startDate)) errors.startDate = 'Start date is required (YYYY-MM-DD)';
    else if (body.startDate < today) errors.startDate = 'Start date cannot be in the past';
    if (!isDate(body.endDate)) errors.endDate = 'End date is required (YYYY-MM-DD)';
    else if (isDate(body.startDate) && body.endDate < body.startDate) errors.endDate = 'End date cannot be before start date';
    if (typeof body.reason !== 'string' || body.reason.replace(/\s/g, '').length < 10) {
      errors.reason = 'Reason must contain at least 10 characters';
    }
    if (!Object.keys(errors).length) {
      const days = dayCount(body.startDate, body.endDate);
      if (days > state.balance) errors.endDate = `Requested ${days} days but only ${state.balance} available`;
      const clash = state.leave.find((r) => r.status !== 'rejected' && body.startDate <= r.endDate && body.endDate >= r.startDate);
      if (clash) errors.startDate = `Overlaps an existing ${clash.status} request (${clash.startDate} to ${clash.endDate})`;
    }
    if (Object.keys(errors).length) return send(res, 422, { message: 'Leave request is invalid', errors });
    const request = {
      id: `LV-${++leaveSeq}`, type: body.type, startDate: body.startDate, endDate: body.endDate,
      reason: body.reason.trim(), status: 'pending', days: dayCount(body.startDate, body.endDate),
    };
    state.balance -= request.days;
    state.leave.push(request);
    if (typeof body.requestId === "string")
      state.leaveByRequestId.set(body.requestId, request);
    send(res, 201, request);
  }

  function send(res, code, payload) {
    const text = JSON.stringify(payload);
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(text);
  }

  async function readJson(req) {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    if (!chunks.length) return {};
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  }

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const route = `${req.method} ${url.pathname}`;
    try {
      if (url.pathname.startsWith('/__mock')) {
        if (!cfg.devControls) return send(res, 404, { message: 'Not found' });
        if (route === 'POST /__mock/scenario') {
          const r = addScenario(await readJson(req));
          return send(res, r.error ? 400 : 200, r);
        }
        if (route === 'DELETE /__mock/scenario') { state.scenarios = []; return send(res, 200, { ok: true }); }
        if (route === "POST /__mock/office") {
          const { latitude, longitude } = await readJson(req);
          if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
            return send(res, 400, {
              message: "latitude and longitude must be numbers",
            });
          }
          cfg.officeLat = latitude;
          cfg.officeLng = longitude;
          return send(res, 200, {
            ok: true,
            officeLat: latitude,
            officeLng: longitude,
          });
        }
        if (route === 'POST /__mock/reset') { state = seed(now(), cfg); return send(res, 200, { ok: true }); }
        if (route === 'GET /__mock/state') {
          return send(res, 200, { scenarios: state.scenarios, events: state.events.size, balance: state.balance });
        }
        return send(res, 404, { message: 'Not found' });
      }

      const slow = takeScenario('slow');
      if (slow) await sleep(slow.delayMs);
      if (takeScenario('server_error')) return send(res, 500, { message: 'Simulated internal server error' });

      if (route === "GET /employee/me") {
        return send(res, 200, {
          ...EMPLOYEE,
          office: {
            latitude: cfg.officeLat,
            longitude: cfg.officeLng,
            radiusMeters: cfg.radiusMeters,
          },
        });
      }
      if (route === 'GET /attendance') {
        const month = url.searchParams.get('month');
        if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month ?? '')) return send(res, 400, { message: 'month must be YYYY-MM' });
        const records = [...state.attendance.entries()]
          .filter(([d]) => d.startsWith(month))
          .sort(([a], [b]) => (a < b ? 1 : -1))
          .map(([date, r]) => ({ date, checkIn: r.checkIn, checkOut: r.checkOut }));
        return send(res, 200, { month, records });
      }
      if (route === 'POST /attendance/events') return await postEvent(req, await readJson(req), res);
      if (route === 'GET /leave/balance') return send(res, 200, { available: state.balance });
      if (route === 'GET /leave/requests') return send(res, 200, { requests: [...state.leave].reverse() });
      if (route === 'POST /leave/requests') return postLeave(await readJson(req), res);
      send(res, 404, { message: 'Not found' });
    } catch (e) {
      if (e instanceof SyntaxError) return send(res, 400, { message: 'Malformed JSON body' });
      console.error(e);
      send(res, 500, { message: 'Unexpected server error' });
    }
  });

  return { server, state: () => state, config: cfg, companyDate: (d) => companyDate(d, cfg.timezone) };
}
