import { ApiError } from "./validation.ts";

export const financeScenarioKinds = ["BASE", "UPSIDE", "DOWNSIDE"] as const;
export type FinanceScenarioKind = (typeof financeScenarioKinds)[number];

export type FinanceScenarioAssumption = {
  code: string;
  label: string;
  amountMinor: string;
  classification: "BUDGET" | "FORECAST";
};

export type ConfigureFinanceScenarioPayload = {
  scenarioKind: FinanceScenarioKind;
  name: string;
  currency: string;
  validFrom: string;
  validTo: string;
  assumptions: FinanceScenarioAssumption[];
  expectedVersion: number | null;
  reason: string;
};

function requireIsoDate(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new ApiError(
      400,
      "finance_scenario_date_invalid",
      `${field} must be an ISO calendar date.`,
    );
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== value
  ) {
    throw new ApiError(
      400,
      "finance_scenario_date_invalid",
      `${field} must be an ISO calendar date.`,
    );
  }
  return value;
}

function stringField(
  value: unknown,
  code: string,
  min: number,
  max: number,
): string {
  if (typeof value !== "string") {
    throw new ApiError(400, code, "Scenario field is invalid.");
  }
  const result = value.trim();
  if (result.length < min || result.length > max) {
    throw new ApiError(400, code, "Scenario field is invalid.");
  }
  return result;
}

function amountMinor(value: unknown): string {
  if (typeof value !== "string" || !/^-?\d+$/.test(value)) {
    throw new ApiError(
      400,
      "finance_scenario_amount_invalid",
      "Scenario amount must be an integer minor-unit string.",
    );
  }
  const parsed = BigInt(value);
  if (parsed < -9_000_000_000_000_000n || parsed > 9_000_000_000_000_000n) {
    throw new ApiError(
      400,
      "finance_scenario_amount_invalid",
      "Scenario amount is outside the supported range.",
    );
  }
  return parsed.toString();
}

function assumptions(value: unknown): FinanceScenarioAssumption[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 100) {
    throw new ApiError(
      400,
      "finance_scenario_assumptions_invalid",
      "Scenario assumptions must contain between 1 and 100 items.",
    );
  }
  const seen = new Set<string>();
  return value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new ApiError(
        400,
        "finance_scenario_assumption_invalid",
        "Scenario assumption is invalid.",
      );
    }
    const row = item as Record<string, unknown>;
    const allowed = new Set(["code", "label", "amountMinor", "classification"]);
    if (Object.keys(row).some((key) => !allowed.has(key))) {
      throw new ApiError(
        400,
        "finance_scenario_field_unsupported",
        "Scenario assumption contains an unsupported field.",
      );
    }
    const code = stringField(row.code, "finance_scenario_code_invalid", 1, 64)
      .toUpperCase();
    if (!/^[A-Z0-9_.-]+$/.test(code) || seen.has(code)) {
      throw new ApiError(
        400,
        "finance_scenario_code_invalid",
        "Scenario assumption code is invalid or duplicated.",
      );
    }
    seen.add(code);
    if (row.classification !== "BUDGET" && row.classification !== "FORECAST") {
      throw new ApiError(
        400,
        "finance_scenario_classification_invalid",
        "Scenario assumptions must be explicitly BUDGET or FORECAST.",
      );
    }
    return {
      code,
      label: stringField(row.label, "finance_scenario_label_invalid", 1, 120),
      amountMinor: amountMinor(row.amountMinor),
      classification: row.classification,
    };
  });
}

export async function parseConfigureFinanceScenarioPayload(
  request: Request,
): Promise<ConfigureFinanceScenarioPayload> {
  let body: Record<string, unknown>;
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    body = value as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "finance_scenario_request_invalid",
      "Request body must be a valid JSON object.",
    );
  }
  const allowed = new Set([
    "scenarioKind",
    "name",
    "currency",
    "validFrom",
    "validTo",
    "assumptions",
    "expectedVersion",
    "reason",
  ]);
  if (Object.keys(body).some((key) => !allowed.has(key))) {
    throw new ApiError(
      400,
      "finance_scenario_field_unsupported",
      "Scenario contains an unsupported field.",
    );
  }
  if (
    !financeScenarioKinds.includes(body.scenarioKind as FinanceScenarioKind)
  ) {
    throw new ApiError(
      400,
      "finance_scenario_kind_invalid",
      "Scenario kind must be BASE, UPSIDE or DOWNSIDE.",
    );
  }
  const currency = stringField(
    body.currency,
    "finance_scenario_currency_invalid",
    3,
    3,
  ).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) {
    throw new ApiError(
      400,
      "finance_scenario_currency_invalid",
      "Currency must be an explicit ISO-style three-letter code.",
    );
  }
  const validFrom = requireIsoDate(body.validFrom, "validFrom");
  const validTo = requireIsoDate(body.validTo, "validTo");
  if (validTo < validFrom) {
    throw new ApiError(
      400,
      "finance_scenario_period_invalid",
      "validTo must not precede validFrom.",
    );
  }
  const expectedVersion = body.expectedVersion === null
    ? null
    : Number.isInteger(body.expectedVersion) &&
        Number(body.expectedVersion) >= 1
    ? Number(body.expectedVersion)
    : (() => {
      throw new ApiError(
        400,
        "finance_scenario_version_invalid",
        "Expected version is invalid.",
      );
    })();
  return {
    scenarioKind: body.scenarioKind as FinanceScenarioKind,
    name: stringField(body.name, "finance_scenario_name_invalid", 1, 120),
    currency,
    validFrom,
    validTo,
    assumptions: assumptions(body.assumptions),
    expectedVersion,
    reason: stringField(
      body.reason,
      "finance_scenario_reason_invalid",
      10,
      1000,
    ),
  };
}

export async function hashFinanceScenarioRequest(
  payload: ConfigureFinanceScenarioPayload,
): Promise<string> {
  const canonical = JSON.stringify({
    version: 1,
    operation: "finance.scenario.configure",
    ...payload,
  });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
