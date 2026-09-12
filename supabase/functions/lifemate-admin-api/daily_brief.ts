import type { KpiValue } from "./analytics_kpi_store.ts";

export type DailyBriefEvidence = {
  id: string;
  metric: string;
  value: number | null;
  state: "ready" | "partial" | "unavailable";
  source: string;
  freshness: { status: "fresh" | "partial" | "unavailable"; asOfUtc: string };
  caveat: string | null;
};

export type DailyBriefItem = {
  id: string;
  severity: "info" | "attention";
  title: string;
  detail: string;
  evidenceIds: string[];
};

export type DailyBrief = {
  state: "ready" | "partial" | "unavailable";
  changes: DailyBriefItem[];
  attention: DailyBriefItem[];
  actions: DailyBriefItem[];
  evidence: DailyBriefEvidence[];
  caveats: string[];
  generatedAtUtc: string;
};

function label(name: string): string {
  if (name === "accounts_created") return "حساب‌های ایجادشده";
  if (name === "monthly_active_accounts") return "حساب‌های فعال ماهانه";
  return name;
}

function evidence(value: KpiValue): DailyBriefEvidence {
  return {
    id: `analytics:${value.name}:v${value.definitionVersion}`,
    metric: value.name,
    value: value.value,
    state: value.state,
    source: value.source,
    freshness: value.freshness,
    caveat: value.reason ?? null,
  };
}

function recentChange(
  value: KpiValue,
  evidenceId: string,
): DailyBriefItem | null {
  const series = value.series;
  if (!series || series.length < 14) return null;

  const comparisonWindow = series.slice(-14);
  // A null data point means the canonical source could not establish a value.
  // Do not coerce that uncertainty to zero and manufacture a trend.
  if (comparisonWindow.some((point) => point.value === null)) return null;

  const values = comparisonWindow.map((point) => point.value as number);
  const recent = values.slice(-7).reduce((sum, point) => sum + point, 0);
  const previous = values.slice(0, 7).reduce((sum, point) => sum + point, 0);
  if (recent === previous) {
    return {
      id: `change:${value.name}`,
      severity: "info",
      title: `${label(value.name)} در دو بازه هفت‌روزه بدون تغییر خالص است`,
      detail:
        `مجموع ۷ روز اخیر ${recent} و ۷ روز قبل نیز ${previous} بوده است. این مقایسه مستقیماً از series canonical ساخته شده است.`,
      evidenceIds: [evidenceId],
    };
  }
  const direction = recent > previous ? "افزایش" : "کاهش";
  return {
    id: `change:${value.name}`,
    severity: recent < previous ? "attention" : "info",
    title: `${label(value.name)} نسبت به ۷ روز قبل ${direction} داشته است`,
    detail:
      `مجموع ۷ روز اخیر ${recent} در برابر ${previous} در ۷ روز قبل است. درصد تغییر عمداً در صورت مبنای صفر محاسبه نمی‌شود.`,
    evidenceIds: [evidenceId],
  };
}

export function buildDailyBrief(
  values: readonly KpiValue[],
  generatedAtUtc: string,
): DailyBrief {
  const allowed = values.filter((value) =>
    value.name === "accounts_created" ||
    value.name === "monthly_active_accounts"
  );
  const evidenceItems = allowed.map(evidence);
  const changes: DailyBriefItem[] = [];
  const attention: DailyBriefItem[] = [];
  const actions: DailyBriefItem[] = [];

  for (const value of allowed) {
    const evidenceId = `analytics:${value.name}:v${value.definitionVersion}`;
    const change = recentChange(value, evidenceId);
    if (change) changes.push(change);

    if (value.state === "unavailable" || value.value === null) {
      attention.push({
        id: `attention:${value.name}:unavailable`,
        severity: "attention",
        title: `${label(value.name)} قابل اتکا نیست`,
        detail:
          "منبع canonical مقدار قابل اتکایی برنگردانده است؛ Daily Brief به‌جای حدس، این مورد را unavailable نگه داشته است.",
        evidenceIds: [evidenceId],
      });
      actions.push({
        id: `action:${value.name}:source`,
        severity: "attention",
        title: `کیفیت منبع ${label(value.name)} را بررسی کنید`,
        detail:
          "این یک اقدام پیشنهادی برای بررسی انسانی read model است و هیچ mutation خودکاری اجرا نمی‌کند.",
        evidenceIds: [evidenceId],
      });
    } else if (
      value.state === "partial" || value.freshness.status !== "fresh"
    ) {
      attention.push({
        id: `attention:${value.name}:partial`,
        severity: "attention",
        title: `${label(value.name)} با caveat داده همراه است`,
        detail: value.reason ??
          "وضعیت freshness این KPI کامل نیست و باید با احتیاط تفسیر شود.",
        evidenceIds: [evidenceId],
      });
    }
  }

  if (evidenceItems.length === 0) {
    return {
      state: "unavailable",
      changes: [],
      attention: [{
        id: "attention:no-evidence",
        severity: "attention",
        title: "Daily Brief داده قابل استناد ندارد",
        detail:
          "هیچ KPI allowlisted از read modelهای approved بازنگشت؛ خروجی مدیریتی ساخته یا حدس زده نشد.",
        evidenceIds: [],
      }],
      actions: [],
      evidence: [],
      caveats: [
        "Daily Brief فقط read-only است و هیچ اقدام خودکاری اجرا نمی‌کند.",
      ],
      generatedAtUtc,
    };
  }

  const state = evidenceItems.some((item) => item.state === "unavailable")
    ? "partial"
    : evidenceItems.some((item) =>
        item.state === "partial" || item.freshness.status !== "fresh"
      )
    ? "partial"
    : "ready";

  return {
    state,
    changes,
    attention,
    actions,
    evidence: evidenceItems,
    caveats: [
      "این خلاصه فقط از KPIهای business allowlisted ساخته می‌شود و شامل raw health data یا توصیه پزشکی نیست.",
      "نبود شواهد trend باعث ساختن تغییر یا درصد فرضی نمی‌شود.",
      "Actions صرفاً پیشنهاد بررسی انسانی هستند و side effect ندارند.",
    ],
    generatedAtUtc,
  };
}
