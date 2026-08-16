import { ApiError, requireUuid } from "./validation.ts";

export const marketingContentGoals = [
  "awareness",
  "launch",
  "education",
  "engagement",
  "retention",
] as const;
export type MarketingContentGoal = (typeof marketingContentGoals)[number];

export const marketingContentTones = [
  "warm",
  "clear",
  "energetic",
  "professional",
] as const;
export type MarketingContentTone = (typeof marketingContentTones)[number];

export const marketingContentLanguages = ["fa", "en"] as const;
export type MarketingContentLanguage =
  (typeof marketingContentLanguages)[number];

export type MarketingAiContentPayload = {
  goal: MarketingContentGoal;
  tone: MarketingContentTone;
  language: MarketingContentLanguage;
  keyMessage: string | null;
  callToAction: string | null;
};

export type MarketingAiCampaignContext = {
  campaignName: string;
  objective: string | null;
  productCode: string | null;
  channelCode: string | null;
  brief: string | null;
};

export type MarketingAiContentVariant = {
  id: string;
  headline: string;
  body: string;
  callToAction: string | null;
  hashtags: string[];
  rationale: string;
};

const GENERATIONS_PATH =
  /^\/api\/v1\/marketing\/campaigns\/([^/]+)\/ai-content\/generations$/i;

export function matchMarketingAiContentGenerationsPath(
  path: string,
): string | null {
  const value = GENERATIONS_PATH.exec(path)?.[1];
  return value ? requireUuid(value, "campaignId") : null;
}

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new Error("invalid");
    }
    return body as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "marketing_ai_content_request_invalid",
      "Content Studio request must be a valid JSON object.",
    );
  }
}

function optionalText(
  value: unknown,
  maximum: number,
  code: string,
): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(400, code, "Content Studio text field is invalid.");
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > maximum) {
    throw new ApiError(400, code, "Content Studio text field is invalid.");
  }
  return normalized;
}

export async function parseMarketingAiContentPayload(
  request: Request,
): Promise<MarketingAiContentPayload> {
  const body = await objectBody(request);
  if (!marketingContentGoals.includes(body.goal as MarketingContentGoal)) {
    throw new ApiError(
      400,
      "marketing_ai_content_goal_invalid",
      "Content goal is not allowlisted.",
    );
  }
  if (!marketingContentTones.includes(body.tone as MarketingContentTone)) {
    throw new ApiError(
      400,
      "marketing_ai_content_tone_invalid",
      "Content tone is not allowlisted.",
    );
  }
  if (
    !marketingContentLanguages.includes(
      body.language as MarketingContentLanguage,
    )
  ) {
    throw new ApiError(
      400,
      "marketing_ai_content_language_invalid",
      "Content language is not allowlisted.",
    );
  }
  return {
    goal: body.goal as MarketingContentGoal,
    tone: body.tone as MarketingContentTone,
    language: body.language as MarketingContentLanguage,
    keyMessage: optionalText(
      body.keyMessage,
      500,
      "marketing_ai_content_key_message_invalid",
    ),
    callToAction: optionalText(
      body.callToAction,
      240,
      "marketing_ai_content_cta_invalid",
    ),
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function hashMarketingAiContentRequest(
  campaignId: string,
  payload: MarketingAiContentPayload,
): Promise<string> {
  return sha256(
    `v1\nmarketing-ai-content\n${campaignId}\n${JSON.stringify(payload)}`,
  );
}

function trimSentence(
  value: string | null,
  fallback: string,
  max = 180,
): string {
  const normalized = (value ?? "").trim().replace(/\s+/g, " ");
  if (!normalized) return fallback;
  return normalized.length <= max
    ? normalized
    : `${normalized.slice(0, Math.max(1, max - 1)).trimEnd()}…`;
}

function productLabel(code: string | null): string {
  switch ((code ?? "").toLowerCase()) {
    case "wellmate":
      return "WellMate";
    case "caremate":
      return "CareMate";
    case "fitmate":
      return "FitMate";
    default:
      return "LifeMate";
  }
}

function faGoal(goal: MarketingContentGoal): string {
  return {
    awareness: "آشنایی",
    launch: "معرفی و لانچ",
    education: "آموزش ساده",
    engagement: "تعامل",
    retention: "بازگشت و همراهی",
  }[goal];
}

function enGoal(goal: MarketingContentGoal): string {
  return {
    awareness: "awareness",
    launch: "launch",
    education: "education",
    engagement: "engagement",
    retention: "retention",
  }[goal];
}

function toneLead(
  tone: MarketingContentTone,
  language: MarketingContentLanguage,
): string {
  if (language === "fa") {
    return {
      warm: "سلامت وقتی ساده‌تر می‌شود که احساس کنیم تنها نیستیم.",
      clear: "یک تجربه ساده برای مدیریت بهتر سلامت و مراقبت روزمره.",
      energetic: "یک قدم کوچک امروز، یک تجربه سلامت منظم‌تر از همین حالا.",
      professional:
        "LifeMate برای ساده‌سازی تجربه سلامت و مراقبت خانوادگی طراحی شده است.",
    }[tone];
  }
  return {
    warm: "Health feels easier when care stays connected and human.",
    clear: "A simpler way to organize everyday health and care.",
    energetic:
      "One small step today can make everyday care feel more organized.",
    professional:
      "LifeMate is designed to simplify everyday health and family-care workflows.",
  }[tone];
}

function defaultCta(
  goal: MarketingContentGoal,
  language: MarketingContentLanguage,
): string {
  if (language === "fa") {
    return goal === "engagement"
      ? "تجربه یا دغدغه‌ات را برای ما بنویس."
      : goal === "retention"
      ? "برگرد و برنامه امروزت را مرور کن."
      : "LifeMate را بیشتر بشناس.";
  }
  return goal === "engagement"
    ? "Tell us what makes everyday care easier for you."
    : goal === "retention"
    ? "Come back and review today’s plan."
    : "Discover more about LifeMate.";
}

function channelHint(
  channelCode: string | null,
  language: MarketingContentLanguage,
): string {
  const channel = (channelCode ?? "general").toLowerCase();
  if (language === "fa") {
    if (channel === "linkedin") {
      return "مناسب لحن حرفه‌ای و اسکن سریع در LinkedIn";
    }
    if (channel === "telegram") return "مناسب متن کوتاه و مستقیم در Telegram";
    if (channel === "instagram") return "مناسب کپشن خوانا و کوتاه در Instagram";
    if (channel === "facebook") return "مناسب متن اجتماعی و توضیحی در Facebook";
    return "نسخه عمومی برای کانال برنامه‌ریزی‌شده کمپین";
  }
  if (channel === "linkedin") {
    return "Optimized for a professional LinkedIn scan";
  }
  if (channel === "telegram") return "Optimized for concise Telegram reading";
  if (channel === "instagram") {
    return "Optimized for a readable Instagram caption";
  }
  if (channel === "facebook") {
    return "Optimized for a conversational Facebook post";
  }
  return "General draft for the campaign’s planned channel";
}

function hashtags(
  context: MarketingAiCampaignContext,
  language: MarketingContentLanguage,
): string[] {
  const product = productLabel(context.productCode).replace(
    /[^A-Za-z0-9]/g,
    "",
  );
  if (language === "fa") {
    return ["#LifeMate", `#${product}`, "#سلامت_دیجیتال"].filter((
      value,
      index,
      all,
    ) => all.indexOf(value) === index);
  }
  return ["#LifeMate", `#${product}`, "#DigitalHealth"].filter((
    value,
    index,
    all,
  ) => all.indexOf(value) === index);
}

export function generateDeterministicMarketingVariants(
  context: MarketingAiCampaignContext,
  payload: MarketingAiContentPayload,
): MarketingAiContentVariant[] {
  const product = productLabel(context.productCode);
  const message = trimSentence(
    payload.keyMessage,
    context.objective ?? context.brief ?? context.campaignName,
  );
  const cta = payload.callToAction ??
    defaultCta(payload.goal, payload.language);
  const tags = hashtags(context, payload.language);
  const lead = toneLead(payload.tone, payload.language);
  const hint = channelHint(context.channelCode, payload.language);

  if (payload.language === "fa") {
    return [
      {
        id: "v1",
        headline: `${product}؛ برای ${faGoal(payload.goal)} ساده و انسانی`,
        body: `${lead}\n\n${message}\n\n${cta}`,
        callToAction: cta,
        hashtags: tags,
        rationale:
          `${hint}؛ پیام اصلی بدون ادعای پزشکی یا داده شخصی نگه داشته شده است.`,
      },
      {
        id: "v2",
        headline: `${context.campaignName} | یک پیام کوتاه از ${product}`,
        body: `${message}\n\n${lead}\n\n${cta}`,
        callToAction: cta,
        hashtags: tags,
        rationale:
          "نسخه دوم ترتیب پیام را عوض می‌کند تا ارزش پیشنهادی زودتر دیده شود و همچنان نیازمند بازبینی انسان است.",
      },
      {
        id: "v3",
        headline: `یک سؤال برای جامعه ${product}`,
        body: `${lead}\n\n${message}\n\n${cta}`,
        callToAction: cta,
        hashtags: tags,
        rationale:
          "نسخه سوم برای تعامل طراحی شده است؛ خروجی Draft است و هیچ انتشار خودکاری انجام نمی‌دهد.",
      },
    ];
  }

  return [
    {
      id: "v1",
      headline: `${product}: a clear path to ${enGoal(payload.goal)}`,
      body: `${lead}\n\n${message}\n\n${cta}`,
      callToAction: cta,
      hashtags: tags,
      rationale: `${hint}; the draft avoids medical claims and personal data.`,
    },
    {
      id: "v2",
      headline: `${context.campaignName} | a short note from ${product}`,
      body: `${message}\n\n${lead}\n\n${cta}`,
      callToAction: cta,
      hashtags: tags,
      rationale:
        "This variant leads with the campaign message and remains a human-review-only draft.",
    },
    {
      id: "v3",
      headline: `A question for the ${product} community`,
      body: `${lead}\n\n${message}\n\n${cta}`,
      callToAction: cta,
      hashtags: tags,
      rationale:
        "This variant is structured for engagement and cannot publish itself.",
    },
  ];
}
