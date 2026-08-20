/**
 * Yagye payment flow — K6 baseline load test
 *
 * Prerequisites:
 *   1. mix run priv/repo/seeds.exs  (prints the dev secret key)
 *   2. mix phx.server               (start the API on :4000)
 *   3. Gateway simulator running on :4100 (or MockProviderAdapter configured)
 *
 * Usage:
 *   SECRET_KEY=sk_sim_xxx k6 run tools/k6/payment_flow.js
 *
 *   # Run only the smoke scenario:
 *   SECRET_KEY=sk_sim_xxx k6 run --env SCENARIO=smoke tools/k6/payment_flow.js
 *
 * Thresholds (fail the run if breached):
 *   - http_req_failed        < 1%    (HTTP-level errors)
 *   - payment_success_rate   > 95%   (payments reaching "succeeded")
 *   - payment_cycle_ms p(95) < 3000  (full create→settled cycle)
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// ── Config ────────────────────────────────────────────────────────────────────

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const SECRET_KEY = __ENV.SECRET_KEY;
const SCENARIO = __ENV.SCENARIO || 'all';

if (!SECRET_KEY) {
  throw new Error(
    'SECRET_KEY is required.\n' +
    'Run `mix run priv/repo/seeds.exs` and pass the printed dev secret key:\n' +
    '  SECRET_KEY=sk_sim_xxx k6 run tools/k6/payment_flow.js'
  );
}

// ── Custom metrics ────────────────────────────────────────────────────────────

const paymentSuccessRate = new Rate('payment_success_rate');
const paymentCycleMs = new Trend('payment_cycle_ms', true);
const pollIterations = new Trend('payment_poll_iterations');

// ── Scenarios ─────────────────────────────────────────────────────────────────

const scenarios = {
  // Quick sanity check — runs before the main load test
  smoke: {
    executor: 'constant-vus',
    vus: 1,
    duration: '30s',
    tags: { scenario: 'smoke' },
  },

  // Baseline load — ramp to 20 VUs, hold, ramp down
  load: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '20s', target: 20 },
      { duration: '60s', target: 20 },
      { duration: '10s', target: 0 },
    ],
    startTime: '35s',
    tags: { scenario: 'load' },
  },

  // Stress — push to 50 VUs to find the saturation point
  stress: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '15s', target: 50 },
      { duration: '30s', target: 50 },
      { duration: '15s', target: 0 },
    ],
    startTime: '2m45s',
    tags: { scenario: 'stress' },
  },
};

export const options = {
  scenarios: SCENARIO === 'all' ? scenarios : { [SCENARIO]: scenarios[SCENARIO] },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    payment_success_rate: ['rate>0.95'],
    'payment_cycle_ms': ['p(95)<3000'],
  },
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function uniqueKey() {
  return `k6-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

const HEADERS = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${SECRET_KEY}`,
  'x-api-version': '2026-01-01',
};

function createPayment() {
  const res = http.post(
    `${BASE_URL}/v1/payments`,
    JSON.stringify({ amount: 10000, currency: 'GHS', rail: 'fiat_provider' }),
    { headers: { ...HEADERS, 'idempotency-key': uniqueKey() } }
  );

  const ok = check(res, {
    'create: status 201': (r) => r.status === 201,
    'create: has id':     (r) => !!r.json('id'),
  });

  if (!ok) return null;
  return res.json('id');
}

function pollUntilSettled(publicId, maxWaitMs = 5000) {
  const deadline = Date.now() + maxWaitMs;
  let iterations = 0;

  while (Date.now() < deadline) {
    iterations++;
    const res = http.get(`${BASE_URL}/v1/payments/${publicId}`, { headers: HEADERS });

    if (res.status !== 200) {
      pollIterations.add(iterations);
      return null;
    }

    const state = res.json('state');
    if (state && state !== 'processing' && state !== 'created') {
      pollIterations.add(iterations);
      return state;
    }

    sleep(0.1);
  }

  pollIterations.add(iterations);
  return 'timeout';
}

function fetchEvents(publicId) {
  const res = http.get(`${BASE_URL}/v1/payments/${publicId}/events`, { headers: HEADERS });
  check(res, { 'events: status 200': (r) => r.status === 200 });
  return res.json('data') || [];
}

// ── Main VU loop ──────────────────────────────────────────────────────────────

export default function () {
  const cycleStart = Date.now();

  // 1. Create payment
  const publicId = createPayment();
  if (!publicId) {
    paymentSuccessRate.add(false);
    return;
  }

  // 2. Poll until settled
  const finalState = pollUntilSettled(publicId);
  const succeeded = finalState === 'succeeded';

  paymentSuccessRate.add(succeeded);
  paymentCycleMs.add(Date.now() - cycleStart);

  check(finalState, {
    'payment: reached succeeded': (s) => s === 'succeeded',
  });

  // 3. Verify events on a subset of requests (1 in 5) to avoid hammering the endpoint
  if (succeeded && Math.random() < 0.2) {
    const events = fetchEvents(publicId);
    check(events, {
      'events: exactly 4': (e) => e.length === 4,
      'events: last is succeeded': (e) => e[e.length - 1]?.event_type === 'payment.succeeded',
    });
  }
}

// ── Summary ───────────────────────────────────────────────────────────────────

export function handleSummary(data) {
  const metrics = data.metrics;

  const successRate = metrics.payment_success_rate?.values?.rate ?? 0;
  const p95Cycle = metrics.payment_cycle_ms?.values?.['p(95)'] ?? 0;
  const avgPoll = metrics.payment_poll_iterations?.values?.avg ?? 0;
  const httpFailRate = metrics.http_req_failed?.values?.rate ?? 0;

  console.log('\n=== Yagye Payment Flow — Summary ===');
  console.log(`Payment success rate : ${(successRate * 100).toFixed(1)}%  (threshold: >95%)`);
  console.log(`Cycle time p(95)     : ${p95Cycle.toFixed(0)}ms  (threshold: <3000ms)`);
  console.log(`Avg poll iterations  : ${avgPoll.toFixed(1)}`);
  console.log(`HTTP failure rate    : ${(httpFailRate * 100).toFixed(2)}%`);
  console.log('=====================================\n');

  return { stdout: '' };
}
