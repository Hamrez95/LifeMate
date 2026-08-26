import {
  hashFinanceScenarioRequest,
  parseConfigureFinanceScenarioPayload,
} from "./finance_scenarios.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

async function rejects(action: () => Promise<unknown>, code: string) {
  try {
    await action();
  } catch (error) {
    if (
      error &&
      typeof error === "object" &&
      "code" in error &&
      error.code === code
    ) return;
    throw error;
  }
  throw new Error(`Expected ${code}`);
}

function request(overrides: Record<string, unknown> = {}) {
  return new Request("https://admin.test/api/v1/finance/scenarios", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      scenarioKind: "BASE",
      name: "Base 2027",
      currency: "USD",
      validFrom: "2027-01-01",
      validTo: "2027-12-31",
      assumptions: [
        {
          code: "REVENUE_CORE",
          label: "Core revenue",
          amountMinor: "12500000",
          classification: "FORECAST",
        },
      ],
      expectedVersion: null,
      reason: "Create the reviewed base operating scenario for planning.",
      ...overrides,
    }),
  });
}

Deno.test(
  "finance scenario parser preserves explicit minor-unit and classification semantics",
  async () => {
    const payload = await parseConfigureFinanceScenarioPayload(request());
    assert(payload.currency === "USD", "currency must remain explicit");
    assert(
      payload.assumptions[0].amountMinor === "12500000",
      "minor-unit amount must remain an integer string",
    );
    assert(
      payload.assumptions[0].classification === "FORECAST",
      "classification must remain explicit",
    );
    assert(
      payload.expectedVersion === null,
      "create semantics must support null expected version",
    );
  },
);

Deno.test(
  "finance scenario parser rejects unsupported fields and implicit classification",
  async () => {
    await rejects(
      () => parseConfigureFinanceScenarioPayload(request({ fxRate: 1.25 })),
      "finance_scenario_field_unsupported",
    );
    await rejects(
      () =>
        parseConfigureFinanceScenarioPayload(
          request({
            assumptions: [{
              code: "REVENUE_CORE",
              label: "Core revenue",
              amountMinor: "100",
            }],
          }),
        ),
      "finance_scenario_classification_invalid",
    );
  },
);

Deno.test(
  "finance scenario parser rejects duplicate codes, decimal amounts and invalid periods",
  async () => {
    await rejects(
      () =>
        parseConfigureFinanceScenarioPayload(
          request({
            assumptions: [
              {
                code: "X",
                label: "One",
                amountMinor: "100",
                classification: "BUDGET",
              },
              {
                code: "x",
                label: "Two",
                amountMinor: "200",
                classification: "FORECAST",
              },
            ],
          }),
        ),
      "finance_scenario_code_invalid",
    );
    await rejects(
      () =>
        parseConfigureFinanceScenarioPayload(
          request({
            assumptions: [{
              code: "X",
              label: "One",
              amountMinor: "12.5",
              classification: "FORECAST",
            }],
          }),
        ),
      "finance_scenario_amount_invalid",
    );
    await rejects(
      () =>
        parseConfigureFinanceScenarioPayload(
          request({ validFrom: "2027-12-31", validTo: "2027-01-01" }),
        ),
      "finance_scenario_period_invalid",
    );
  },
);

Deno.test(
  "finance scenario idempotency hash binds currency, version and assumptions",
  async () => {
    const payload = await parseConfigureFinanceScenarioPayload(request());
    const original = await hashFinanceScenarioRequest(payload);
    const changed = await hashFinanceScenarioRequest({
      ...payload,
      currency: "EUR",
    });
    assert(
      original.length === 64 && original !== changed,
      "request hash must bind financial semantics",
    );
  },
);
