import fs from 'node:fs';

const input = process.argv[2] || 'runtime-pressure.ndjson';
const output = process.argv[3] || 'runtime-pressure-summary.json';
const lines = fs.existsSync(input)
  ? fs.readFileSync(input, 'utf8').split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  : [];

if (lines.length === 0) {
  throw new Error(`No runtime-pressure samples found in ${input}`);
}

const samples = lines.map((line, index) => {
  try {
    return JSON.parse(line);
  } catch (error) {
    throw new Error(`Invalid JSON sample at line ${index + 1}: ${error.message}`);
  }
});

const numericMax = (path) => {
  let maximum = null;
  for (const sample of samples) {
    let value = sample;
    for (const segment of path) value = value?.[segment];
    const number = Number(value);
    if (Number.isFinite(number)) maximum = maximum === null ? number : Math.max(maximum, number);
  }
  return maximum;
};

const outboxNumericMax = {};
for (const sample of samples) {
  const outbox = sample?.outbox;
  if (!outbox || typeof outbox !== 'object' || Array.isArray(outbox)) continue;
  for (const [key, raw] of Object.entries(outbox)) {
    const number = Number(raw);
    if (!Number.isFinite(number)) continue;
    outboxNumericMax[key] = Math.max(outboxNumericMax[key] ?? number, number);
  }
}

const summary = {
  schemaVersion: 'lifemate.runtime-pressure.v1',
  samples: samples.length,
  sampledFromUtc: samples[0]?.sampledAtUtc ?? null,
  sampledToUtc: samples.at(-1)?.sampledAtUtc ?? null,
  database: {
    maxConnections: numericMax(['database', 'maxConnections']),
    peakDatabaseConnections: numericMax(['database', 'databaseConnections']),
    peakLifeMateRuntimeConnections: numericMax(['database', 'lifeMateRuntimeConnections']),
    peakWaitingRuntimeConnections: numericMax(['database', 'waitingRuntimeConnections']),
    peakRuntimeQueriesOverOneSecond: numericMax(['database', 'runtimeQueriesOverOneSecond']),
  },
  outboxNumericMax,
};

fs.writeFileSync(output, `${JSON.stringify(summary, null, 2)}\n`);

console.log('LifeMate runtime pressure summary');
console.log(`  samples: ${summary.samples}`);
console.log(`  peak DB connections: ${summary.database.peakDatabaseConnections ?? 'n/a'} / ${summary.database.maxConnections ?? 'n/a'}`);
console.log(`  peak LifeMate runtime connections: ${summary.database.peakLifeMateRuntimeConnections ?? 'n/a'}`);
console.log(`  peak waiting runtime connections: ${summary.database.peakWaitingRuntimeConnections ?? 'n/a'}`);
console.log(`  peak runtime queries >1s: ${summary.database.peakRuntimeQueriesOverOneSecond ?? 'n/a'}`);
