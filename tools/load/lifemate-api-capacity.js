import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  Counter,
  Rate,
  Trend,
} from 'k6/metrics';

const PRODUCTION_PROJECT_REF = 'bwdvmniywyyijjauipnh';
const profile = (__ENV.LOAD_PROFILE || 'smoke').trim().toLowerCase();
const targetMode = (__ENV.LIFEMATE_LOAD_TARGET || 'local').trim().toLowerCase();
const baseUrl = (__ENV.BASE_URL || 'http://127.0.0.1:18080').replace(/\/+$/, '');
const targetProjectRef = (__ENV.TARGET_PROJECT_REF || '').trim();
const legacyAccessToken = (__ENV.ACCESS_TOKEN || '').trim();
const runId = sanitizeRunId(__ENV.RUN_ID || `${Date.now()}`);
const mutationConfirmation = (__ENV.CONFIRM_SYNTHETIC_MUTATIONS || '').trim();
const writeFixtureMinimum = 25;

const unexpectedResponses = new Rate('unexpected_response_rate');
const controlledOverload = new Rate('controlled_overload_rate');
const serverErrors = new Rate('server_error_rate');
const missingCorrelation = new Rate('missing_correlation_id_rate');
const criticalWriteFailures = new Rate('critical_write_failure_rate');
const replayMissing = new Rate('idempotency_replay_missing_rate');
const retryRecovered = new Rate('retry_recovered_rate');
const apiLatency = new Trend('lifemate_api_latency_ms', true);
const response2xx = new Counter('response_2xx');
const response4xx = new Counter('response_4xx');
const response5xx = new Counter('response_5xx');
const response429 = new Counter('response_429');
const response503 = new Counter('response_503');

const profileDefinitions = {
  smoke: {
    identityPoolMinimum: 1,
    maxControlledOverloadRate: 0.01,
    scenarios: {
      api: {
        executor: 'constant-arrival-rate',
        rate: 2,
        timeUnit: '1s',
        duration: '30s',
        preAllocatedVUs: 2,
        maxVUs: 8,
      },
    },
  },
  'single-user-throttle': {
    identityPoolMinimum: 1,
    minControlledOverloadRate: 0.02,
    singleIdentityOnly: true,
    scenarios: {
      api: {
        executor: 'constant-arrival-rate',
        rate: 10,
        timeUnit: '1s',
        duration: '60s',
        preAllocatedVUs: 8,
        maxVUs: 24,
      },
    },
  },
  'read-heavy': {
    identityPoolMinimum: 20,
    maxControlledOverloadRate: 0.01,
    scenarios: {
      api: {
        executor: 'constant-arrival-rate',
        rate: 100,
        timeUnit: '1s',
        duration: '2m',
        preAllocatedVUs: 80,
        maxVUs: 250,
      },
    },
  },
  ramp: {
    identityPoolMinimum: 100,
    maxControlledOverloadRate: 0.05,
    scenarios: {
      api: {
        executor: 'ramping-arrival-rate',
        startRate: 25,
        timeUnit: '1s',
        preAllocatedVUs: 150,
        maxVUs: 800,
        stages: [
          { target: 100, duration: '1m' },
          { target: 100, duration: '1m' },
          { target: 250, duration: '1m' },
          { target: 250, duration: '2m' },
          { target: 500, duration: '1m' },
          { target: 500, duration: '4m' },
        ],
      },
    },
  },
  spike: {
    identityPoolMinimum: 350,
    scenarios: {
      api: {
        executor: 'ramping-arrival-rate',
        startRate: 50,
        timeUnit: '1s',
        preAllocatedVUs: 500,
        maxVUs: 2600,
        stages: [
          { target: 2000, duration: '10s' },
          { target: 2000, duration: '40s' },
          { target: 50, duration: '10s' },
        ],
      },
      recovery: {
        executor: 'constant-arrival-rate',
        rate: 25,
        timeUnit: '1s',
        duration: '60s',
        startTime: '70s',
        preAllocatedVUs: 30,
        maxVUs: 100,
      },
    },
  },
  soak: {
    // Hosted access tokens have a 60-minute lifetime. Keep one invocation
    // safely below that boundary; a certified 60+ minute soak must rotate
    // sessions between bounded segments rather than running on expired JWTs.
    identityPoolMinimum: 50,
    maxControlledOverloadRate: 0.01,
    scenarios: {
      api: {
        executor: 'constant-arrival-rate',
        rate: 250,
        timeUnit: '1s',
        duration: '50m',
        preAllocatedVUs: 200,
        maxVUs: 700,
      },
    },
  },
  'care-mix': {
    identityPoolMinimum: 25,
    maxControlledOverloadRate: 0.01,
    scenarios: {
      api: {
        executor: 'constant-arrival-rate',
        rate: 100,
        timeUnit: '1s',
        duration: '3m',
        preAllocatedVUs: 80,
        maxVUs: 250,
      },
    },
  },
  'write-heavy': {
    identityPoolMinimum: writeFixtureMinimum,
    maxControlledOverloadRate: 0.05,
    scenarios: {
      api: {
        executor: 'constant-vus',
        vus: writeFixtureMinimum,
        duration: '5m',
      },
    },
  },
  'retry-storm': {
    identityPoolMinimum: writeFixtureMinimum,
    scenarios: {
      api: {
        executor: 'constant-vus',
        vus: writeFixtureMinimum,
        duration: '3m',
      },
    },
  },
};

if (!Object.prototype.hasOwnProperty.call(profileDefinitions, profile)) {
  throw new Error(`Unsupported LOAD_PROFILE: ${profile}`);
}

const profileDefinition = profileDefinitions[profile];
const authSessions = loadAuthSessions();
const authSessionBySubject = Object.fromEntries(
  authSessions.map((session) => [session.subject, session]),
);
validateTarget();
const fixtures = loadDoseFixtures();

const thresholds = {
  unexpected_response_rate: ['rate<0.01'],
  server_error_rate: ['rate<0.005'],
  missing_correlation_id_rate: ['rate<0.001'],
  lifemate_api_latency_ms: ['p(95)<1500', 'p(99)<3000'],
  critical_write_failure_rate: ['rate<0.01'],
  idempotency_replay_missing_rate: ['rate<0.01'],
};
if (Number.isFinite(profileDefinition.maxControlledOverloadRate)) {
  thresholds.controlled_overload_rate = [
    `rate<${profileDefinition.maxControlledOverloadRate}`,
  ];
}
if (Number.isFinite(profileDefinition.minControlledOverloadRate)) {
  thresholds.controlled_overload_rate = [
    `rate>${profileDefinition.minControlledOverloadRate}`,
  ];
}

export const options = {
  discardResponseBodies: false,
  scenarios: profileDefinition.scenarios,
  thresholds,
};

let writeState = null;

export default function () {
  if (profile === 'write-heavy' || profile === 'retry-storm') {
    runCriticalWriteIteration();
    if (profile === 'write-heavy') {
      // One logical mutation generates an original request plus an exact replay.
      // Pace the normal write profile so one subject does not exceed the
      // 120-request/min critical-write admission ceiling by construction.
      sleep(1);
    }
    return;
  }
  if (profile === 'care-mix') {
    runCareReadMix();
    return;
  }
  runReadMix(profile === 'smoke');
}

function runReadMix(smokeOnly) {
  const pick = __ITER % (smokeOnly ? 2 : 4);
  const today = new Date().toISOString().slice(0, 10);
  if (pick === 0) {
    request('GET', '/health', null, { auth: false });
  } else if (pick === 1) {
    requestWithBackoff('GET', '/api/v1/me');
  } else if (pick === 2) {
    requestWithBackoff(
      'GET',
      `/api/v1/home-snapshot?fromDate=${today}&toDate=${today}`,
    );
  } else {
    requestWithBackoff(
      'GET',
      `/api/v1/dose-occurrences?fromDate=${today}&toDate=${today}`,
    );
  }
}

function runCareReadMix() {
  const pick = __ITER % 3;
  if (pick === 0) {
    requestWithBackoff('GET', '/api/v1/care/relationships');
  } else if (pick === 1) {
    requestWithBackoff('GET', '/api/v1/care/invitations');
  } else {
    const today = new Date().toISOString().slice(0, 10);
    requestWithBackoff(
      'GET',
      `/api/v1/dose-occurrences?fromDate=${today}&toDate=${today}`,
    );
  }
}

function runCriticalWriteIteration() {
  if (writeState === null) {
    const fixture = fixtures[(__VU - 1) % fixtures.length];
    const session = targetMode === 'staging'
      ? authSessionBySubject[fixture.subject]
      : null;
    if (targetMode === 'staging' && !session) {
      throw new Error(
        `Dose fixture subject has no matching authenticated session: ${fixture.subject}`,
      );
    }
    writeState = {
      id: fixture.id,
      version: Number(fixture.version),
      nextStatus: fixture.status === 'taken' ? 'skipped' : 'taken',
      subject: fixture.subject,
      accessToken: session?.accessToken || '',
    };
  }

  const logicalRequestId = uuidV4();
  const body = JSON.stringify({
    clientRequestId: logicalRequestId,
    version: writeState.version,
    status: writeState.nextStatus,
    occurredAtUtc: new Date().toISOString(),
  });
  const path = `/api/v1/dose-occurrences/${writeState.id}/report`;
  const first = requestWithBackoff('POST', path, body, {
    idempotencyKey: logicalRequestId,
    criticalWrite: true,
    accessToken: writeState.accessToken,
  });

  if (first.status >= 200 && first.status < 300) {
    let parsed;
    try {
      parsed = first.json();
    } catch (_) {
      criticalWriteFailures.add(true);
      return;
    }
    const nextVersion = Number(parsed.version);
    if (!Number.isInteger(nextVersion) || nextVersion <= writeState.version) {
      criticalWriteFailures.add(true);
      return;
    }

    const replay = request('POST', path, body, {
      idempotencyKey: logicalRequestId,
      criticalWrite: true,
      accessToken: writeState.accessToken,
    });
    const replayHeader = headerValue(replay, 'X-Idempotency-Replayed');
    const replayOk = replay.status >= 200 && replay.status < 300 &&
      replayHeader.toLowerCase() === 'true';
    replayMissing.add(!replayOk);
    criticalWriteFailures.add(!replayOk);

    writeState.version = nextVersion;
    writeState.nextStatus = writeState.nextStatus === 'taken' ? 'skipped' : 'taken';
  } else if (!isControlledOverload(first.status)) {
    criticalWriteFailures.add(true);
  }
}

function requestWithBackoff(method, path, body = null, requestOptions = {}) {
  const first = request(method, path, body, requestOptions);
  if (!isControlledOverload(first.status)) return first;

  const retryAfter = Number.parseFloat(headerValue(first, 'Retry-After'));
  const delaySeconds = Number.isFinite(retryAfter)
    ? Math.max(0.05, Math.min(2, retryAfter))
    : 0.25;
  sleep(delaySeconds);
  const second = request(method, path, body, requestOptions);
  retryRecovered.add(second.status >= 200 && second.status < 300);
  return second;
}

function request(method, path, body = null, requestOptions = {}) {
  const headers = {
    Accept: 'application/json',
  };
  if (requestOptions.auth !== false) {
    const token = requestOptions.accessToken || selectAccessToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }
  if (body !== null) {
    headers['Content-Type'] = 'application/json';
  }
  if (requestOptions.idempotencyKey) {
    headers['Idempotency-Key'] = requestOptions.idempotencyKey;
  }

  const response = http.request(method, `${baseUrl}${path}`, body, {
    headers,
    timeout: '20s',
    tags: {
      lifemate_profile: profile,
      lifemate_path: normalizedPathTag(path),
    },
  });

  const duration = Number(response.timings?.duration || 0);
  apiLatency.add(duration);
  recordStatus(response.status);
  const correlationId = headerValue(response, 'X-Correlation-Id');
  missingCorrelation.add(correlationId.length === 0);

  const accepted = response.status >= 200 && response.status < 300;
  const overloaded = isControlledOverload(response.status);
  controlledOverload.add(overloaded);
  serverErrors.add(response.status >= 500 && response.status !== 503);
  unexpectedResponses.add(!accepted && !overloaded);

  check(response, {
    'response is useful or controlled overload': (value) =>
      (value.status >= 200 && value.status < 300) ||
      isControlledOverload(value.status),
    'correlation id is present': () => correlationId.length > 0,
  });

  return response;
}

function selectAccessToken() {
  if (authSessions.length === 0) return '';
  if (profileDefinition.singleIdentityOnly) {
    return authSessions[0].accessToken;
  }
  const index = Math.abs((__VU - 1) + __ITER) % authSessions.length;
  return authSessions[index].accessToken;
}

function recordStatus(status) {
  if (status >= 200 && status < 300) response2xx.add(1);
  if (status >= 400 && status < 500) response4xx.add(1);
  if (status >= 500) response5xx.add(1);
  if (status === 429) response429.add(1);
  if (status === 503) response503.add(1);
}

function isControlledOverload(status) {
  return status === 429 || status === 503;
}

function headerValue(response, name) {
  const wanted = name.toLowerCase();
  for (const [key, value] of Object.entries(response.headers || {})) {
    if (key.toLowerCase() === wanted) return String(value || '');
  }
  return '';
}

function loadAuthSessions() {
  const raw = (__ENV.AUTH_SESSIONS_JSON || '').trim();
  let values = [];
  if (raw) {
    try {
      values = JSON.parse(raw);
    } catch (_) {
      throw new Error('AUTH_SESSIONS_JSON must be a JSON array.');
    }
  } else if (legacyAccessToken) {
    values = [{ accessToken: legacyAccessToken, subject: 'legacy-single-user' }];
  }

  if (!Array.isArray(values)) {
    throw new Error('AUTH_SESSIONS_JSON must be a JSON array.');
  }
  const normalized = values.map((value, index) => {
    if (!value || typeof value !== 'object') {
      throw new Error(`Auth session ${index} must be an object.`);
    }
    const accessToken = String(value.accessToken || '').trim();
    const subject = String(value.subject || '').trim();
    if (!accessToken || !subject || subject.length > 128) {
      throw new Error(`Auth session ${index} is invalid.`);
    }
    return { accessToken, subject };
  });
  if (new Set(normalized.map((value) => value.subject)).size !== normalized.length) {
    throw new Error('AUTH_SESSIONS_JSON subjects must be unique.');
  }
  return normalized;
}

function loadDoseFixtures() {
  if (profile !== 'write-heavy' && profile !== 'retry-storm') return [];
  if (
    targetMode === 'staging' &&
    mutationConfirmation !== 'STAGING-SYNTHETIC-MUTATIONS'
  ) {
    throw new Error(
      'Mutation profiles require CONFIRM_SYNTHETIC_MUTATIONS=STAGING-SYNTHETIC-MUTATIONS.',
    );
  }

  const raw = (__ENV.DOSE_FIXTURES_JSON || '').trim();
  let values;
  if (!raw && targetMode === 'local') {
    values = Array.from({ length: writeFixtureMinimum }, (_, index) => ({
      id: deterministicFixtureUuid(index + 1),
      version: 1,
      status: 'scheduled',
      subject: `local-subject-${String(index + 1).padStart(3, '0')}`,
    }));
  } else {
    try {
      values = JSON.parse(raw);
    } catch (_) {
      throw new Error('DOSE_FIXTURES_JSON must be a JSON array.');
    }
  }

  if (!Array.isArray(values) || values.length < writeFixtureMinimum) {
    throw new Error(
      `Mutation profiles require at least ${writeFixtureMinimum} synthetic dose fixtures.`,
    );
  }
  return values.map((value, index) => {
    if (!value || typeof value !== 'object') {
      throw new Error(`Dose fixture ${index} must be an object.`);
    }
    const id = String(value.id || '').trim();
    const version = Number(value.version);
    const status = String(value.status || 'scheduled').trim().toLowerCase();
    const subject = String(value.subject || value.authUserId || '').trim();
    if (!isUuid(id) || !Number.isInteger(version) || version < 1) {
      throw new Error(`Dose fixture ${index} is invalid.`);
    }
    if (targetMode === 'staging' && (!subject || !authSessionBySubject[subject])) {
      throw new Error(
        `Dose fixture ${index} must name a subject present in AUTH_SESSIONS_JSON.`,
      );
    }
    return { id, version, status, subject };
  });
}

function validateTarget() {
  if (targetMode === 'local') {
    if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/i.test(baseUrl)) {
      throw new Error('Local load target must be localhost/127.0.0.1.');
    }
    return;
  }

  if (targetMode !== 'staging') {
    throw new Error(
      'LIFEMATE_LOAD_TARGET must be local or staging. Production is unsupported.',
    );
  }
  if ((__ENV.CONFIRM_STAGING_LOAD || '').trim() !== 'LIFEMATE-STAGING-ONLY') {
    throw new Error(
      'Remote load requires CONFIRM_STAGING_LOAD=LIFEMATE-STAGING-ONLY.',
    );
  }
  if (!/^[a-z0-9]{12,40}$/i.test(targetProjectRef)) {
    throw new Error('TARGET_PROJECT_REF is required for staging load.');
  }
  if (targetProjectRef === PRODUCTION_PROJECT_REF) {
    throw new Error('Production project ref is explicitly blocked from load tests.');
  }
  if (!baseUrl.startsWith('https://')) {
    throw new Error('Staging load target must use HTTPS.');
  }
  if (!baseUrl.includes(targetProjectRef)) {
    throw new Error('BASE_URL must belong to TARGET_PROJECT_REF.');
  }
  if (baseUrl.includes(PRODUCTION_PROJECT_REF)) {
    throw new Error('Production API URL is explicitly blocked from load tests.');
  }
  if (authSessions.length < profileDefinition.identityPoolMinimum) {
    throw new Error(
      `Profile ${profile} requires at least ${profileDefinition.identityPoolMinimum} unique synthetic auth sessions; received ${authSessions.length}.`,
    );
  }
  if (profileDefinition.singleIdentityOnly && authSessions.length !== 1) {
    throw new Error('single-user-throttle requires exactly one synthetic identity.');
  }
}

function normalizedPathTag(path) {
  return path
    .replace(/[0-9a-f]{8}-[0-9a-f-]{27}/gi, ':id')
    .replace(/\?.*$/, '');
}

function sanitizeRunId(value) {
  const cleaned = String(value).replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 48);
  return cleaned || 'load';
}

function uuidV4() {
  const template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
  return template.replace(/[xy]/g, (value) => {
    const random = Math.floor(Math.random() * 16);
    const nibble = value === 'x' ? random : (random & 0x3) | 0x8;
    return nibble.toString(16);
  });
}

function deterministicFixtureUuid(index) {
  return `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`;
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function handleSummary(data) {
  const compact = {
    schemaVersion: 'lifemate.capacity.v1',
    runId,
    target: targetMode,
    targetProjectRef: targetMode === 'staging' ? targetProjectRef : 'local',
    profile,
    identityPoolSize: authSessions.length,
    identityPoolMinimum: targetMode === 'staging'
      ? profileDefinition.identityPoolMinimum
      : 0,
    thresholdsPassed: allThresholdsPassed(data),
    requests: metricValue(data, 'http_reqs', 'count'),
    achievedRps: metricValue(data, 'http_reqs', 'rate'),
    droppedIterations: metricValue(data, 'dropped_iterations', 'count'),
    latencyMs: {
      p50: metricValue(data, 'lifemate_api_latency_ms', 'p(50)'),
      p95: metricValue(data, 'lifemate_api_latency_ms', 'p(95)'),
      p99: metricValue(data, 'lifemate_api_latency_ms', 'p(99)'),
      max: metricValue(data, 'lifemate_api_latency_ms', 'max'),
    },
    responses: {
      success2xx: metricValue(data, 'response_2xx', 'count'),
      client4xx: metricValue(data, 'response_4xx', 'count'),
      server5xx: metricValue(data, 'response_5xx', 'count'),
      rateLimited429: metricValue(data, 'response_429', 'count'),
      overloaded503: metricValue(data, 'response_503', 'count'),
    },
    rates: {
      unexpected: metricValue(data, 'unexpected_response_rate', 'rate'),
      controlledOverload: metricValue(data, 'controlled_overload_rate', 'rate'),
      serverError: metricValue(data, 'server_error_rate', 'rate'),
      missingCorrelationId: metricValue(
        data,
        'missing_correlation_id_rate',
        'rate',
      ),
      criticalWriteFailure: metricValue(
        data,
        'critical_write_failure_rate',
        'rate',
      ),
      idempotencyReplayMissing: metricValue(
        data,
        'idempotency_replay_missing_rate',
        'rate',
      ),
      retryRecovered: metricValue(data, 'retry_recovered_rate', 'rate'),
    },
  };

  const human = [
    '',
    'LifeMate capacity summary',
    `  target/profile: ${compact.target}/${compact.profile}`,
    `  identities: ${compact.identityPoolSize} (minimum ${compact.identityPoolMinimum})`,
    `  thresholds: ${compact.thresholdsPassed ? 'PASS' : 'FAIL'}`,
    `  requests: ${fmt(compact.requests)}  achieved RPS: ${fmt(compact.achievedRps)}`,
    `  latency ms p50/p95/p99/max: ${fmt(compact.latencyMs.p50)} / ${fmt(compact.latencyMs.p95)} / ${fmt(compact.latencyMs.p99)} / ${fmt(compact.latencyMs.max)}`,
    `  responses 2xx/4xx/5xx/429/503: ${fmt(compact.responses.success2xx)} / ${fmt(compact.responses.client4xx)} / ${fmt(compact.responses.server5xx)} / ${fmt(compact.responses.rateLimited429)} / ${fmt(compact.responses.overloaded503)}`,
    `  dropped iterations: ${fmt(compact.droppedIterations)}`,
    '',
  ].join('\n');

  return {
    stdout: human,
    'load-summary.json': JSON.stringify(data, null, 2),
    'capacity-result.json': JSON.stringify(compact, null, 2),
  };
}

function metricValue(data, metric, key) {
  const value = data.metrics?.[metric]?.values?.[key];
  return Number.isFinite(value) ? value : 0;
}

function allThresholdsPassed(data) {
  for (const metric of Object.values(data.metrics || {})) {
    for (const threshold of Object.values(metric.thresholds || {})) {
      if (threshold && threshold.ok === false) return false;
    }
  }
  return true;
}

function fmt(value) {
  return Number(value || 0).toFixed(2);
}
