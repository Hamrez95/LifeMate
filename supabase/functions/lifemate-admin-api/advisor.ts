import type { AdminCapabilitySnapshot } from "./authorization.ts";
import type { AnalyticsKpiQuery, KpiValue } from "./analytics_kpis.ts";
import { ApiError } from "./validation.ts";

export const advisorTopics = [
  "product_overview",
  "acquisition",
  "activity",
] as const;
export type AdvisorTopic = (typeof advisorTopics)[number];

export type AdvisorRequest = {
  topic: AdvisorTopic;
  question: string | null;
};

export type AdvisorEvidence = {
  sourceId: string;
  label: string;
  state: "ready" | "partial" | "unavailable";
  value: number | null;
  numerator: number | null;
  denominator: number | null;
  source: string;
  freshness: {
    status: "fresh" | "partial" | "unavailable";
    asOfUtc: string;
  };
  caveat: string | null;
};

export type AdvisorFinding = {
  severity: "info" | "attention";
  title: string;
  detail: string;
  evidenceIds: string[];
};

export type AdvisorInsight = {
  topic: AdvisorTopic;
  mode: "deterministic";
  summary: string;
  findings: AdvisorFinding[];
  evidence: AdvisorEvidence[];
  caveats: string[];
  generatedAtUtc: string;
};

const TOPIC_PERMISSIONS: Record<AdvisorTopic, readonly string[]> = {
  product_overview: ["analytics.read"],
  acquisition: ["analytics.read"],
  activity: ["analytics.read"],
};

const TOPIC_KPIS: Record<AdvisorTopic, readonly string[]> = {
  product_overview: ["accounts_created", "monthly_active_accounts"],
  acquisition: ["accounts_created"],
  activity: ["monthly_active_accounts"],
};

function objectBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "advisor_request_invalid", "Advisor request must be a JSON object.");
  }
  return value as Record<string, unknown>;
}

export async function parseAdvisorRequest(request: Request): Promise<AdvisorRequest> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(400, "advisor_request_invalid", "Advisor request must be valid JSON.");
  }
  const value = objectBody(body);
  if (!advisorTopics.includes(value.topic as AdvisorTopic)) {
    throw new ApiError(400, "advisor_topic_invalid", "Advisor topic is not allowlisted.");
  }
  let question: string | null = null;
  if (value.question !== undefined && value.question !== null && value.question !== "") {
    if (typeof value.question !== "string") {
      throw new ApiError(400, "advisor_question_invalid", "Advisor question is invalid.");
    }
    question = value.question.trim();
    if (question.length < 2 || question.length > 500) {
      throw new ApiError(400, "advisor_question_invalid", "Advisor question must be between 2 and 500 characters.");
    }
  }
  return { topic: value.topic as AdvisorTopic, question };
}

export function advisorSourcePermissions(topic: AdvisorTopic): readonly string[] {
  return TOPIC_PERMISSIONS[topic];
}

export function assertAdvisorSourcePermissions(
  admin: AdminCapabilitySnapshot,
  topic: AdvisorTopic,
): void {
  const current = new Set(admin.permissions);
  const missing = TOPIC_PERMISSIONS[topic].filter((permission) => !current.has(permission));
  if (missing.length > 0) {
    throw new ApiError(
      403,
      "advisor_source_forbidden",
      "The requested advisor topic requires additional source permissions.",
    );
  }
}

export function advisorKpiNames(topic: AdvisorTopic): readonly string[] {
  return TOPIC_KPIS[topic];
}

export function advisorKpiQuery(now = new Date()): AnalyticsKpiQuery {
  const to = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const from = new Date(to);
  from.setUTCDate(from.getUTCDate() - 29);
  return {
    from: from.toISOString().slice(0, 10),
    to: to.toISOString().slice(0, 10),
    product: null,
    includeSeries: false,
  };
}

function evidence(value: KpiValue): AdvisorEvidence {
  return {
    sourceId: `analytics:${value.name}:v${value.definitionVersion}`,
    label: value.name,
    state: value.state,
    value: value.value,
    numerator: value.numerator,
    denominator: value.denominator,
    source: value.source,
    freshness: value.freshness,
    caveat: value.reason ?? null,
  };
}

function readableKpi(name: string): string {
  switch (name) {
    case "accounts_created":
      return "حساب‌های ایجادشده";
    case "monthly_active_accounts":
      return "حساب‌های فعال ماهانه";
    default:
      return name;
  }
}

function findingFor(value: AdvisorEvidence): AdvisorFinding {
  if (value.state === "unavailable" || value.value === null) {
    return {
      severity: "attention",
      title: `${readableKpi(value.label)} قابل ارزیابی نیست`,
      detail: "Read model این شاخص مقدار قابل اتکایی برنگردانده است؛ نتیجه به‌جای حدس یا صفر ساختگی، unavailable نگه داشته شد.",
      evidenceIds: [value.sourceId],
    };
  }
  if (value.state === "partial" || value.freshness.status !== "fresh") {
    return {
      severity: "attention",
      title: `${readableKpi(value.label)} نیازمند توجه به تازگی داده است`,
      detail: `مقدار ثبت‌شده ${value.value} است، اما وضعیت داده ${value.freshness.status} است و باید با احتیاط تفسیر شود.`,
      evidenceIds: [value.sourceId],
    };
  }
  return {
    severity: "info",
    title: `${readableKpi(value.label)} از read model معتبر خوانده شد`,
    detail: `مقدار فعلی در بازه ۳۰روزه ${value.value} است. این عدد مستقیماً از منبع allowlisted آمده و توسط Advisor ساخته نشده است.`,
    evidenceIds: [value.sourceId],
  };
}

export function buildAdvisorInsight(
  topic: AdvisorTopic,
  values: readonly KpiValue[],
  generatedAtUtc: string,
): AdvisorInsight {
  const allowlisted = new Set(advisorKpiNames(topic));
  const selected = values.filter((value) => allowlisted.has(value.name)).map(evidence);
  const byName = new Set(selected.map((item) => item.label));
  for (const name of advisorKpiNames(topic)) {
    if (!byName.has(name)) {
      selected.push({
        sourceId: `analytics:${name}:missing`,
        label: name,
        state: "unavailable",
        value: null,
        numerator: null,
        denominator: null,
        source: "approved analytics read model",
        freshness: { status: "unavailable", asOfUtc: generatedAtUtc },
        caveat: "The allowlisted KPI was not returned by the source.",
      });
    }
  }
  const findings = selected.map(findingFor);
  const availableCount = selected.filter((item) => item.value !== null && item.state !== "unavailable").length;
  const summary = availableCount === 0
    ? "برای این موضوع هنوز داده کافی از read modelهای مجاز وجود ندارد؛ Advisor عمداً نتیجه‌ای را حدس نمی‌زند."
    : `Advisor برای این موضوع ${availableCount} شاخص قابل استناد را از read modelهای مجاز بررسی کرد. نتیجه فقط بر پایه همین شواهد است.`;
  return {
    topic,
    mode: "deterministic",
    summary,
    findings,
    evidence: selected,
    caveats: [
      "این خروجی تشخیص پزشکی، توصیه درمانی یا جایگزین تصمیم انسانی نیست.",
      "متن سؤال فقط داده ورودی غیرقابل اعتماد است و اجازه تغییر منبع، مجوز یا اجرای SQL نمی‌دهد.",
      "Advisor فقط read modelهای allowlisted را می‌خواند و هیچ mutation یا side effect خارجی انجام نمی‌دهد.",
    ],
    generatedAtUtc,
  };
}

export function safeAdvisorLogFields(request: AdvisorRequest): Record<string, unknown> {
  return {
    topic: request.topic,
    hasQuestion: request.question !== null,
    questionLength: request.question?.length ?? 0,
  };
}
