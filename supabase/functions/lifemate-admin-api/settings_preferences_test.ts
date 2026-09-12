import {
  hashConfigureCommandCenterPreferencesRequest,
  parseConfigureCommandCenterPreferencesPayload,
} from "./settings_preferences.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

async function rejects(action: () => Promise<unknown>, code: string) {
  try {
    await action();
  } catch (error) {
    if (
      error && typeof error === "object" && "code" in error &&
      error.code === code
    ) return;
    throw error;
  }
  throw new Error(`Expected ${code}`);
}

const request = (body: Record<string, unknown>) =>
  new Request("https://admin.test/api/v1/settings/preferences", {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

Deno.test("Command Center preferences parse only allow-listed mutable fields", async () => {
  const payload = await parseConfigureCommandCenterPreferencesPayload(request({
    locale: "fa-IR",
    timeZone: "Asia/Tehran",
    displayName: "LifeMate Command Center",
    expectedVersion: 1,
    reason: "Align the reviewed Command Center display preferences.",
  }));
  assert(payload.locale === "fa-IR", "locale must parse");
  assert(payload.timeZone === "Asia/Tehran", "time zone must parse");
  assert(payload.expectedVersion === 1, "version must parse");

  await rejects(() =>
    parseConfigureCommandCenterPreferencesPayload(request({
      locale: "fa-IR",
      timeZone: "Asia/Tehran",
      displayName: "LifeMate Command Center",
      expectedVersion: 1,
      reason: "Attempt to inject a provider credential into settings.",
      apiKey: "secret",
    })), "settings_field_unsupported");
});

Deno.test("Command Center preferences validate locale, timezone, version and reason", async () => {
  await rejects(() =>
    parseConfigureCommandCenterPreferencesPayload(request({
      locale: "xx-YY",
      timeZone: "UTC",
      displayName: "LifeMate",
      expectedVersion: 1,
      reason: "Reject an unsupported locale safely and explicitly.",
    })), "settings_locale_invalid");

  await rejects(() =>
    parseConfigureCommandCenterPreferencesPayload(request({
      locale: "en-US",
      timeZone: "Mars/Olympus_Mons",
      displayName: "LifeMate",
      expectedVersion: 1,
      reason: "Reject a timezone that looks structured but is not IANA-backed.",
    })), "settings_timezone_invalid");

  await rejects(() =>
    parseConfigureCommandCenterPreferencesPayload(request({
      locale: "en-US",
      timeZone: "UTC",
      displayName: "LifeMate",
      expectedVersion: 0,
      reason: "Reject a stale invalid optimistic version safely.",
    })), "settings_version_invalid");

  await rejects(() =>
    parseConfigureCommandCenterPreferencesPayload(request({
      locale: "en-US",
      timeZone: "UTC",
      displayName: "LifeMate",
      expectedVersion: 1,
      reason: "short",
    })), "settings_reason_invalid");
});

Deno.test("Command Center preferences hash binds mutable values and version", async () => {
  const payload = await parseConfigureCommandCenterPreferencesPayload(request({
    locale: "en-US",
    timeZone: "UTC",
    displayName: "LifeMate Command Center",
    expectedVersion: 4,
    reason: "Apply the reviewed global display preferences safely.",
  }));
  const original = await hashConfigureCommandCenterPreferencesRequest(payload);
  const changed = await hashConfigureCommandCenterPreferencesRequest({
    ...payload,
    displayName: "LifeMate Admin",
  });
  assert(
    original.length === 64 && original !== changed,
    "hash must bind settings request",
  );
});
