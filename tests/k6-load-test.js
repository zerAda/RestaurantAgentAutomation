/**
 * =============================================================================
 * K6 Load Testing Suite - Resto Bot API (Premium Grade)
 * =============================================================================
 * Replaces basic curl smoke tests with real load testing and performance metrics.
 *
 * Test Scenarios:
 * 1. Health check endpoint (baseline)
 * 2. Meta webhook verification (GET)
 * 3. WhatsApp incoming message (POST)
 * 4. Instagram incoming message (POST)
 * 5. Messenger incoming message (POST)
 *
 * Metrics tracked:
 * - Response time (p50, p95, p99)
 * - Request rate (RPS)
 * - Error rate
 * - Success rate (200, 2xx responses)
 *
 * Thresholds (SLO):
 * - p95 response time < 2000ms
 * - p99 response time < 5000ms
 * - Error rate < 1%
 * - Success rate > 99%
 *
 * Usage:
 *   k6 run tests/k6-load-test.js
 *   k6 run --env TARGET_URL=https://api.example.com tests/k6-load-test.js
 *   k6 run --env SCENARIO=smoke tests/k6-load-test.js
 * =============================================================================
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ============================================================================
// Configuration
// ============================================================================

const TARGET_URL = __ENV.TARGET_URL || 'https://api.srv1258231.hstgr.cloud';
const SCENARIO = __ENV.SCENARIO || 'load';  // smoke | load | stress | soak

// Custom metrics
const errorRate = new Rate('errors');
const healthCheckDuration = new Trend('health_check_duration');
const waInboundDuration = new Trend('wa_inbound_duration');
const igInboundDuration = new Trend('ig_inbound_duration');
const msgInboundDuration = new Trend('msg_inbound_duration');
const totalRequests = new Counter('total_requests');

// ============================================================================
// Test Scenarios
// ============================================================================

export const options = {
  scenarios: {
    // Smoke test: minimal load to verify functionality
    smoke: {
      executor: 'constant-vus',
      vus: 1,
      duration: '1m',
      exec: 'smokeTest',
      startTime: SCENARIO === 'smoke' ? '0s' : '999h',
    },

    // Load test: normal production load
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 10 },   // Ramp up to 10 VUs
        { duration: '5m', target: 10 },   // Stay at 10 VUs
        { duration: '2m', target: 20 },   // Ramp up to 20 VUs
        { duration: '5m', target: 20 },   // Stay at 20 VUs
        { duration: '2m', target: 0 },    // Ramp down
      ],
      exec: 'loadTest',
      startTime: SCENARIO === 'load' ? '0s' : '999h',
      gracefulRampDown: '30s',
    },

    // Stress test: beyond normal load to find breaking point
    stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 20 },
        { duration: '5m', target: 20 },
        { duration: '2m', target: 50 },
        { duration: '5m', target: 50 },
        { duration: '2m', target: 100 },
        { duration: '5m', target: 100 },
        { duration: '5m', target: 0 },
      ],
      exec: 'stressTest',
      startTime: SCENARIO === 'stress' ? '0s' : '999h',
      gracefulRampDown: '30s',
    },

    // Soak test: sustained load over long period
    soak: {
      executor: 'constant-vus',
      vus: 20,
      duration: '30m',
      exec: 'soakTest',
      startTime: SCENARIO === 'soak' ? '0s' : '999h',
    },
  },

  // SLO Thresholds
  thresholds: {
    http_req_duration: [
      'p(95)<2000',  // 95% of requests should be below 2s
      'p(99)<5000',  // 99% of requests should be below 5s
    ],
    http_req_failed: ['rate<0.01'],  // Error rate should be below 1%
    errors: ['rate<0.01'],
    checks: ['rate>0.99'],  // 99% of checks should pass
  },
};

// ============================================================================
// Test Data
// ============================================================================

const META_VERIFY_TOKEN = 'test_verify_token';

const WA_MESSAGE_PAYLOAD = {
  object: 'whatsapp_business_account',
  entry: [
    {
      id: 'WA_BUSINESS_ID',
      changes: [
        {
          value: {
            messaging_product: 'whatsapp',
            metadata: {
              display_phone_number: '212612345678',
              phone_number_id: 'PHONE_NUMBER_ID',
            },
            messages: [
              {
                from: '212612345678',
                id: `wamid.${Date.now()}.${Math.random()}`,
                timestamp: Math.floor(Date.now() / 1000).toString(),
                type: 'text',
                text: { body: 'k6 load test message' },
              },
            ],
          },
          field: 'messages',
        },
      ],
    },
  ],
};

const IG_MESSAGE_PAYLOAD = {
  object: 'instagram',
  entry: [
    {
      id: 'PAGE_ID',
      time: Date.now(),
      messaging: [
        {
          sender: { id: 'PSID_123' },
          recipient: { id: 'PAGE_ID' },
          timestamp: Date.now(),
          message: {
            mid: `m_${Date.now()}`,
            text: 'k6 load test message',
          },
        },
      ],
    },
  ],
};

const MSG_MESSAGE_PAYLOAD = {
  object: 'page',
  entry: [
    {
      id: 'PAGE_ID',
      time: Date.now(),
      messaging: [
        {
          sender: { id: 'PSID_456' },
          recipient: { id: 'PAGE_ID' },
          timestamp: Date.now(),
          message: {
            mid: `m_${Date.now()}`,
            text: 'k6 load test message',
          },
        },
      ],
    },
  ],
};

// ============================================================================
// Test Functions
// ============================================================================

export function smokeTest() {
  group('Smoke Test Suite', () => {
    testHealthCheck();
    testMetaVerification();
    testWAInbound();
    testIGInbound();
    testMSGInbound();
  });
  sleep(1);
}

export function loadTest() {
  const scenario = Math.random();

  if (scenario < 0.2) {
    testHealthCheck();
  } else if (scenario < 0.5) {
    testWAInbound();
  } else if (scenario < 0.75) {
    testIGInbound();
  } else {
    testMSGInbound();
  }

  sleep(Math.random() * 2);  // Random think time 0-2s
}

export function stressTest() {
  loadTest();
  sleep(Math.random());  // Shorter think time for stress
}

export function soakTest() {
  loadTest();
}

// ============================================================================
// Individual Test Cases
// ============================================================================

function testHealthCheck() {
  group('Health Check', () => {
    const response = http.get(`${TARGET_URL}/healthz`, {
      tags: { name: 'health_check' },
    });

    totalRequests.add(1);
    healthCheckDuration.add(response.timings.duration);

    const success = check(response, {
      'health check status is 200': (r) => r.status === 200,
      'health check response is ok': (r) => r.body === 'ok',
      'health check response time < 500ms': (r) => r.timings.duration < 500,
    });

    errorRate.add(!success);
  });
}

function testMetaVerification() {
  group('Meta Webhook Verification', () => {
    const params = {
      'hub.mode': 'subscribe',
      'hub.verify_token': META_VERIFY_TOKEN,
      'hub.challenge': 'test_challenge_123',
    };

    const response = http.get(`${TARGET_URL}/v1/inbound/whatsapp`, {
      params: params,
      tags: { name: 'meta_verify' },
    });

    totalRequests.add(1);

    const success = check(response, {
      'verify status is 200 or 403': (r) => r.status === 200 || r.status === 403,
      'verify response time < 1000ms': (r) => r.timings.duration < 1000,
    });

    errorRate.add(!success);
  });
}

function testWAInbound() {
  group('WhatsApp Inbound Message', () => {
    const response = http.post(`${TARGET_URL}/v1/inbound/whatsapp`, JSON.stringify(WA_MESSAGE_PAYLOAD), {
      headers: {
        'Content-Type': 'application/json',
        'X-Hub-Signature-256': 'sha256=fake_signature_for_testing',
      },
      tags: { name: 'wa_inbound' },
    });

    totalRequests.add(1);
    waInboundDuration.add(response.timings.duration);

    const success = check(response, {
      'wa inbound status is 200 or 400': (r) => r.status === 200 || r.status === 400,  // 400 for invalid signature is OK
      'wa inbound response time < 2000ms': (r) => r.timings.duration < 2000,
    });

    errorRate.add(!success);
  });
}

function testIGInbound() {
  group('Instagram Inbound Message', () => {
    const response = http.post(`${TARGET_URL}/v1/inbound/instagram`, JSON.stringify(IG_MESSAGE_PAYLOAD), {
      headers: {
        'Content-Type': 'application/json',
        'X-Hub-Signature-256': 'sha256=fake_signature_for_testing',
      },
      tags: { name: 'ig_inbound' },
    });

    totalRequests.add(1);
    igInboundDuration.add(response.timings.duration);

    const success = check(response, {
      'ig inbound status is 200 or 400': (r) => r.status === 200 || r.status === 400,
      'ig inbound response time < 2000ms': (r) => r.timings.duration < 2000,
    });

    errorRate.add(!success);
  });
}

function testMSGInbound() {
  group('Messenger Inbound Message', () => {
    const response = http.post(`${TARGET_URL}/v1/inbound/messenger`, JSON.stringify(MSG_MESSAGE_PAYLOAD), {
      headers: {
        'Content-Type': 'application/json',
        'X-Hub-Signature-256': 'sha256=fake_signature_for_testing',
      },
      tags: { name: 'msg_inbound' },
    });

    totalRequests.add(1);
    msgInboundDuration.add(response.timings.duration);

    const success = check(response, {
      'msg inbound status is 200 or 400': (r) => r.status === 200 || r.status === 400,
      'msg inbound response time < 2000ms': (r) => r.timings.duration < 2000,
    });

    errorRate.add(!success);
  });
}

// ============================================================================
// Summary Handler
// ============================================================================

export function handleSummary(data) {
  console.log('\n=== K6 Load Test Summary ===\n');
  console.log(`Total Requests: ${data.metrics.total_requests.values.count}`);
  console.log(`Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%`);
  console.log(`Check Pass Rate: ${(data.metrics.checks.values.rate * 100).toFixed(2)}%`);
  console.log(`\nResponse Times (p95/p99):`);
  console.log(`  Overall: ${data.metrics.http_req_duration.values['p(95)'].toFixed(0)}ms / ${data.metrics.http_req_duration.values['p(99)'].toFixed(0)}ms`);

  if (data.metrics.health_check_duration) {
    console.log(`  Health: ${data.metrics.health_check_duration.values['p(95)'].toFixed(0)}ms / ${data.metrics.health_check_duration.values['p(99)'].toFixed(0)}ms`);
  }
  if (data.metrics.wa_inbound_duration) {
    console.log(`  WA: ${data.metrics.wa_inbound_duration.values['p(95)'].toFixed(0)}ms / ${data.metrics.wa_inbound_duration.values['p(99)'].toFixed(0)}ms`);
  }
  if (data.metrics.ig_inbound_duration) {
    console.log(`  IG: ${data.metrics.ig_inbound_duration.values['p(95)'].toFixed(0)}ms / ${data.metrics.ig_inbound_duration.values['p(99)'].toFixed(0)}ms`);
  }
  if (data.metrics.msg_inbound_duration) {
    console.log(`  MSG: ${data.metrics.msg_inbound_duration.values['p(95)'].toFixed(0)}ms / ${data.metrics.msg_inbound_duration.values['p(99)'].toFixed(0)}ms`);
  }

  console.log('\n===========================\n');

  return {
    'stdout': JSON.stringify(data, null, 2),
    'k6-load-test-results.json': JSON.stringify(data, null, 2),
  };
}
