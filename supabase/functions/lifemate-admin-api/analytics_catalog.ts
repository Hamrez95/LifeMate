export type AnalyticsInstrumentationState =
  | "instrumented"
  | "partial"
  | "planned";
export type AnalyticsKpiAvailability = "available" | "partial" | "unavailable";

export type AnalyticsEventDefinition = {
  name: string;
  definitionVersion: number;
  domain: string;
  instrumentationState: AnalyticsInstrumentationState;
  descriptionFa: string;
  source: string;
  privacyPolicy: string;
};

export type AnalyticsFunnelMetadata = {
  id: "activation";
  stageOrder: number;
  previousStage: string | null;
  privacyThreshold: number;
};

export type AnalyticsKpiDefinition = {
  name: string;
  displayNameFa: string;
  definitionVersion: number;
  unit: "count" | "rate";
  formula: string;
  numerator: string;
  denominator: string | null;
  timeWindow: string;
  timezone: "Asia/Tehran";
  exclusions: string[];
  eventSources: string[];
  freshnessRule: string;
  availability: AnalyticsKpiAvailability;
  funnel?: AnalyticsFunnelMetadata;
};

export const EVENT_TAXONOMY_VERSION = 1;
export const KPI_DICTIONARY_VERSION = 2;
export const ACTIVATION_FUNNEL_PRIVACY_THRESHOLD = 5;

export const ANALYTICS_EVENTS: readonly AnalyticsEventDefinition[] = [
  {
    name: "account_created",
    definitionVersion: 1,
    domain: "identity",
    instrumentationState: "partial",
    descriptionFa: "ایجاد حساب LifeMate بدون اطلاعات تماس یا داده سلامت.",
    source: "identity.accounts lifecycle",
    privacyPolicy:
      "Account lifecycle only; no contact values or health payload.",
  },
  {
    name: "app_enrolled",
    definitionVersion: 1,
    domain: "product",
    instrumentationState: "partial",
    descriptionFa: "عضویت حساب در یک محصول LifeMate در سطح lifecycle.",
    source: "ecosystem.app_enrollments.enrolled_at_utc",
    privacyPolicy:
      "Account/product lifecycle only; no contact, profile or health payload.",
  },
  {
    name: "app_activation_observed",
    definitionVersion: 1,
    domain: "product",
    instrumentationState: "partial",
    descriptionFa:
      "مشاهده فعالیت برای همان عضویت محصول بر اساس snapshot آخرین فعالیت.",
    source: "ecosystem.app_enrollments.last_active_at_utc current snapshot",
    privacyPolicy:
      "Aggregate activation state only; no session content or health payload.",
  },
  {
    name: "profile_completed",
    definitionVersion: 1,
    domain: "profile",
    instrumentationState: "planned",
    descriptionFa: "تکمیل پروفایل پایه بدون ارسال محتوای پروفایل در رویداد.",
    source: "profile lifecycle event producer (planned)",
    privacyPolicy: "Completion state only; no profile field payload.",
  },
  {
    name: "app_opened",
    definitionVersion: 1,
    domain: "product",
    instrumentationState: "planned",
    descriptionFa: "باز شدن محصول برای سنجش استفاده، بدون محتوای سلامت.",
    source: "product telemetry event producer (planned)",
    privacyPolicy: "Product/session telemetry only; no health content.",
  },
  {
    name: "treatment_created",
    definitionVersion: 1,
    domain: "treatment",
    instrumentationState: "planned",
    descriptionFa: "ثبت رویداد ایجاد درمان صرفاً برای شمارش aggregate.",
    source: "treatment lifecycle event producer (planned)",
    privacyPolicy: "No treatment, medication, diagnosis or free-text details.",
  },
  {
    name: "care_invitation_created",
    definitionVersion: 1,
    domain: "care",
    instrumentationState: "planned",
    descriptionFa: "ایجاد دعوت مراقب بدون متن دعوت یا اطلاعات حساس.",
    source: "care invitation lifecycle event producer (planned)",
    privacyPolicy: "No invitation body, contact value or health payload.",
  },
  {
    name: "care_relationship_activated",
    definitionVersion: 1,
    domain: "care",
    instrumentationState: "planned",
    descriptionFa: "فعال شدن Relationship؛ مستقل از Consent و Access Grant.",
    source: "care relationship lifecycle event producer (planned)",
    privacyPolicy:
      "Relationship lifecycle only; does not imply consent or data access.",
  },
  {
    name: "trial_started",
    definitionVersion: 1,
    domain: "commerce",
    instrumentationState: "planned",
    descriptionFa: "شروع دوره آزمایشی بدون داده پرداخت.",
    source: "commerce lifecycle event producer (planned)",
    privacyPolicy:
      "No payment credential, provider secret or raw provider payload.",
  },
  {
    name: "subscription_started",
    definitionVersion: 1,
    domain: "commerce",
    instrumentationState: "planned",
    descriptionFa: "شروع اشتراک در سطح lifecycle.",
    source: "commerce lifecycle event producer (planned)",
    privacyPolicy: "Subscription lifecycle only; no payment secrets.",
  },
  {
    name: "subscription_renewed",
    definitionVersion: 1,
    domain: "commerce",
    instrumentationState: "planned",
    descriptionFa: "تمدید اشتراک در سطح lifecycle.",
    source: "commerce lifecycle event producer (planned)",
    privacyPolicy: "Subscription lifecycle only; no payment secrets.",
  },
  {
    name: "subscription_expired",
    definitionVersion: 1,
    domain: "commerce",
    instrumentationState: "planned",
    descriptionFa: "انقضای اشتراک در سطح lifecycle.",
    source: "commerce lifecycle event producer (planned)",
    privacyPolicy: "Subscription lifecycle only; no payment secrets.",
  },
  {
    name: "promotion_redeemed",
    definitionVersion: 1,
    domain: "commerce",
    instrumentationState: "planned",
    descriptionFa: "استفاده از promotion بدون داده پرداخت یا PII غیرضروری.",
    source: "promotion lifecycle event producer (planned)",
    privacyPolicy: "Redemption lifecycle only; no payment secrets.",
  },
  {
    name: "support_ticket_created",
    definitionVersion: 1,
    domain: "support",
    instrumentationState: "planned",
    descriptionFa: "ایجاد تیکت بدون متن آزاد یا محتوای حساس تیکت.",
    source: "support lifecycle event producer (planned)",
    privacyPolicy: "No ticket body, attachment or health/free-text payload.",
  },
  {
    name: "social_post_published",
    definitionVersion: 1,
    domain: "marketing",
    instrumentationState: "planned",
    descriptionFa: "انتشار محتوای تأییدشده انسانی در سطح lifecycle.",
    source: "marketing publishing lifecycle event producer (planned)",
    privacyPolicy:
      "Human-approved publishing lifecycle only; no provider token.",
  },
  {
    name: "incident_created",
    definitionVersion: 1,
    domain: "operations",
    instrumentationState: "planned",
    descriptionFa: "ایجاد incident بدون log dump، secret یا داده سلامت.",
    source: "operations incident lifecycle event producer (planned)",
    privacyPolicy: "Incident lifecycle only; no secrets, logs or PHI.",
  },
] as const;

export const KPI_DEFINITIONS: readonly AnalyticsKpiDefinition[] = [
  {
    name: "accounts_created",
    displayNameFa: "حساب‌های ایجادشده",
    definitionVersion: 1,
    unit: "count",
    formula: "count(account_created)",
    numerator: "count(account_created)",
    denominator: null,
    timeWindow: "selected date range",
    timezone: "Asia/Tehran",
    exclusions: [
      "Deleted accounts are excluded from snapshot-derived fallback reads.",
    ],
    eventSources: ["account_created"],
    freshnessRule:
      "Unavailable until canonical history or an explicitly marked partial snapshot is supplied.",
    availability: "partial",
  },
  {
    name: "activation_enrolled_accounts",
    displayNameFa: "ورودی قیف فعال‌سازی",
    definitionVersion: 1,
    unit: "count",
    formula: "count(distinct account with app_enrolled in selected cohort)",
    numerator: "distinct accounts enrolled in the selected date/product cohort",
    denominator: null,
    timeWindow: "app-enrollment cohort within selected date range",
    timezone: "Asia/Tehran",
    exclusions: ["Deleted accounts", "Disabled applications"],
    eventSources: ["app_enrolled"],
    freshnessRule:
      "Relational lifecycle fact; aggregate values below the privacy threshold are suppressed.",
    availability: "partial",
    funnel: {
      id: "activation",
      stageOrder: 1,
      previousStage: null,
      privacyThreshold: ACTIVATION_FUNNEL_PRIVACY_THRESHOLD,
    },
  },
  {
    name: "activation_observed_accounts",
    displayNameFa: "فعال‌سازی مشاهده‌شده",
    definitionVersion: 1,
    unit: "count",
    formula:
      "count(distinct cohort account whose same enrollment has last_active_at_utc >= enrolled_at_utc and <= cohort end)",
    numerator: "distinct activated accounts in the enrollment cohort",
    denominator: "activation_enrolled_accounts",
    timeWindow:
      "app-enrollment cohort within selected date range, observed through selected end date",
    timezone: "Asia/Tehran",
    exclusions: [
      "Deleted accounts",
      "Disabled applications",
      "Activity after selected end date",
    ],
    eventSources: ["app_enrolled", "app_activation_observed"],
    freshnessRule:
      "Partial because last_active_at_utc is a current snapshot rather than canonical app-open history; small aggregates are suppressed.",
    availability: "partial",
    funnel: {
      id: "activation",
      stageOrder: 2,
      previousStage: "activation_enrolled_accounts",
      privacyThreshold: ACTIVATION_FUNNEL_PRIVACY_THRESHOLD,
    },
  },
  {
    name: "activation_observed_rate",
    displayNameFa: "نرخ فعال‌سازی مشاهده‌شده",
    definitionVersion: 1,
    unit: "rate",
    formula: "activation_observed_accounts / activation_enrolled_accounts",
    numerator: "activation_observed_accounts",
    denominator: "activation_enrolled_accounts",
    timeWindow:
      "same enrollment cohort and observation window as activation funnel",
    timezone: "Asia/Tehran",
    exclusions: [
      "Suppressed small cohorts",
      "Deleted accounts",
      "Disabled applications",
    ],
    eventSources: ["app_enrolled", "app_activation_observed"],
    freshnessRule:
      "Computed only by Core from the canonical funnel cohort; unavailable when either aggregate is suppressed.",
    availability: "partial",
  },
  {
    name: "profile_completion_rate",
    displayNameFa: "نرخ تکمیل پروفایل",
    definitionVersion: 1,
    unit: "rate",
    formula: "profile_completed / account_created",
    numerator: "distinct accounts with profile_completed",
    denominator: "distinct accounts with account_created in the cohort",
    timeWindow: "account-created cohort within selected date range",
    timezone: "Asia/Tehran",
    exclusions: [
      "Deleted accounts",
      "Events without a valid cohort definition",
    ],
    eventSources: ["account_created", "profile_completed"],
    freshnessRule: "Unavailable while profile_completed is not instrumented.",
    availability: "unavailable",
  },
  {
    name: "monthly_active_accounts",
    displayNameFa: "کاربران فعال ماهانه",
    definitionVersion: 1,
    unit: "count",
    formula: "count(distinct account with app_opened in trailing 30 days)",
    numerator: "distinct accounts with app_opened",
    denominator: null,
    timeWindow: "trailing 30 days ending at selected end date",
    timezone: "Asia/Tehran",
    exclusions: ["Deleted accounts", "Non-user operational traffic"],
    eventSources: ["app_opened"],
    freshnessRule:
      "Unavailable until app_opened telemetry is instrumented; partial snapshots must be labeled partial.",
    availability: "unavailable",
  },
  {
    name: "care_relationship_activation_rate",
    displayNameFa: "نرخ فعال‌سازی ارتباط مراقبتی",
    definitionVersion: 1,
    unit: "rate",
    formula: "care_relationship_activated / care_invitation_created",
    numerator:
      "distinct care invitations resulting in care_relationship_activated",
    denominator: "distinct care_invitation_created",
    timeWindow: "invitation cohort within selected date range",
    timezone: "Asia/Tehran",
    exclusions: ["Revoked invitations before acceptance", "Test fixtures"],
    eventSources: ["care_invitation_created", "care_relationship_activated"],
    freshnessRule:
      "Unavailable until both care lifecycle events are instrumented.",
    availability: "unavailable",
  },
  {
    name: "treatment_creators",
    displayNameFa: "کاربران سازنده درمان",
    definitionVersion: 1,
    unit: "count",
    formula: "count(distinct account with treatment_created)",
    numerator: "distinct accounts with treatment_created",
    denominator: null,
    timeWindow: "selected date range",
    timezone: "Asia/Tehran",
    exclusions: ["Synthetic/test accounts"],
    eventSources: ["treatment_created"],
    freshnessRule:
      "Unavailable until privacy-safe treatment_created instrumentation exists.",
    availability: "unavailable",
  },
  {
    name: "trial_to_subscription_conversion_rate",
    displayNameFa: "نرخ تبدیل آزمایشی به اشتراک",
    definitionVersion: 1,
    unit: "rate",
    formula: "subscription_started after trial_started / trial_started",
    numerator:
      "distinct trials followed by subscription_started within the conversion window",
    denominator: "distinct trial_started",
    timeWindow: "trial cohort; conversion window 30 days",
    timezone: "Asia/Tehran",
    exclusions: [
      "Administrative grants",
      "Complimentary entitlements without a trial",
    ],
    eventSources: ["trial_started", "subscription_started"],
    freshnessRule:
      "Unavailable until both trial and subscription lifecycle events are instrumented.",
    availability: "unavailable",
  },
  {
    name: "subscription_renewal_rate",
    displayNameFa: "نرخ تمدید اشتراک",
    definitionVersion: 1,
    unit: "rate",
    formula: "subscription_renewed / subscriptions eligible for renewal",
    numerator: "distinct subscription_renewed",
    denominator: "distinct subscriptions reaching renewal eligibility",
    timeWindow: "renewal eligibility within selected date range",
    timezone: "Asia/Tehran",
    exclusions: [
      "Cancelled before renewal eligibility",
      "Refunded before renewal eligibility",
    ],
    eventSources: ["subscription_renewed", "subscription_expired"],
    freshnessRule:
      "Unavailable until renewal eligibility and lifecycle event history are instrumented.",
    availability: "unavailable",
  },
  {
    name: "support_tickets_created",
    displayNameFa: "تیکت‌های پشتیبانی ایجادشده",
    definitionVersion: 1,
    unit: "count",
    formula: "count(support_ticket_created)",
    numerator: "count(support_ticket_created)",
    denominator: null,
    timeWindow: "selected date range",
    timezone: "Asia/Tehran",
    exclusions: ["Spam/test tickets"],
    eventSources: ["support_ticket_created"],
    freshnessRule:
      "Unavailable until support ticket lifecycle instrumentation exists.",
    availability: "unavailable",
  },
  {
    name: "social_posts_published",
    displayNameFa: "پست‌های منتشرشده",
    definitionVersion: 1,
    unit: "count",
    formula: "count(social_post_published)",
    numerator: "count(social_post_published)",
    denominator: null,
    timeWindow: "selected date range",
    timezone: "Asia/Tehran",
    exclusions: ["Failed or cancelled publish attempts"],
    eventSources: ["social_post_published"],
    freshnessRule:
      "Unavailable until human-approved publishing lifecycle events are instrumented.",
    availability: "unavailable",
  },
  {
    name: "incidents_created",
    displayNameFa: "رخدادهای عملیاتی ایجادشده",
    definitionVersion: 1,
    unit: "count",
    formula: "count(incident_created)",
    numerator: "count(incident_created)",
    denominator: null,
    timeWindow: "selected date range",
    timezone: "Asia/Tehran",
    exclusions: ["Test incidents"],
    eventSources: ["incident_created"],
    freshnessRule:
      "Unavailable until incident lifecycle instrumentation exists.",
    availability: "unavailable",
  },
] as const;

export function getAnalyticsCatalog() {
  return {
    eventTaxonomyVersion: EVENT_TAXONOMY_VERSION,
    kpiDictionaryVersion: KPI_DICTIONARY_VERSION,
    events: ANALYTICS_EVENTS,
    kpis: KPI_DEFINITIONS,
    generatedAtUtc: new Date().toISOString(),
  };
}
