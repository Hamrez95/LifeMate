from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


path = Path("supabase/functions/lifemate-api/index.ts")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    'import { createCareEventStore } from "./care_events.ts";\n',
    'import { createCareEventStore } from "./care_events.ts";\n'
    'import { createAccountLifecycleStore } from "./account_lifecycle.ts";\n'
    'import { createAuthorizationStore } from "./authorization.ts";\n'
    'import { createIdentityBridge, type ProviderIdentity } from "./identity_bridge.ts";\n',
    "runtime imports",
)

validation_anchor = '''import {
  ApiError,
  normalizeOptional,
  normalizePath,
  readJsonObject,
} from "./validation.ts";
'''
text = replace_once(
    text,
    validation_anchor,
    validation_anchor
    + '\ntype AuthenticatedUser = AuthUser & {\n  identities: ProviderIdentity[];\n};\n',
    "authenticated user type",
)

# Stores are created next to the existing domain stores so they share the same
# bounded database configuration and do not fan out connections.
anchor = 'const careEvents = createCareEventStore(databaseUrl);\n'
text = replace_once(
    text,
    anchor,
    anchor
    + 'const authorizationStore = createAuthorizationStore(databaseUrl);\n'
    + 'const identityBridge = createIdentityBridge(databaseUrl);\n'
    + 'const accountLifecycle = createAccountLifecycleStore(databaseUrl);\n',
    "store initialization",
)

text = replace_once(
    text,
    '  auth: AuthUser,\n): Promise<Response> {\n',
    '  auth: AuthenticatedUser,\n): Promise<Response> {\n',
    "route auth type",
)

text = replace_once(
    text,
    '    return json(await db.bootstrapUser(auth, await readJsonObject(request)));\n',
    '    const bootstrapped = await db.bootstrapUser(\n'
    '      auth,\n'
    '      await readJsonObject(request),\n'
    '    );\n'
    '    const accountId = String(bootstrapped.id ?? "");\n'
    '    if (accountId) {\n'
    '      await identityBridge.syncExternalIdentities(accountId, auth);\n'
    '    }\n'
    '    return json(bootstrapped);\n',
    "bootstrap identity sync",
)

identity_anchor = '  const identity = await db.requireIdentity(auth);\n\n'
identity_routes = '''  const identity = await db.requireIdentity(auth);

  if (request.method === "GET" && path === "/api/v1/capabilities") {
    return json(await authorizationStore.capabilitySnapshot(identity.appUserId));
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/me/identities/sync"
  ) {
    enforceRateLimit(`identity-sync:${identity.appUserId}`, 10, 60 * 60_000);
    return json({
      providers: await identityBridge.syncExternalIdentities(
        identity.appUserId,
        auth,
      ),
    });
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/account/deletion-requests/latest"
  ) {
    return json(
      await accountLifecycle.latestDeletionRequest(identity.appUserId),
    );
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/account/deletion-requests"
  ) {
    enforceRateLimit(`account-deletion:${identity.appUserId}`, 3, 24 * 60 * 60_000);
    const deletion = await accountLifecycle.requestDeletion(identity.appUserId);

    // The database account is disabled synchronously, so subsequent API calls
    // are denied even if a short-lived JWT still exists. Global logout is an
    // additional best-effort session invalidation; the outbox worker is the
    // durable path. Never log the Authorization header.
    const authorizationHeader = request.headers.get("authorization");
    if (authorizationHeader) {
      await fetch(`${supabaseUrl}/auth/v1/logout?scope=global`, {
        method: "POST",
        headers: {
          Authorization: authorizationHeader,
          apikey: publishableKey,
        },
        signal: AbortSignal.timeout(5_000),
      }).catch(() => undefined);
    }
    return json(deletion, 202);
  }

'''
text = replace_once(text, identity_anchor, identity_routes, "account/capability routes")

text = replace_once(
    text,
    '  if (request.method === "GET" && careDoseMatch) {\n    const url = new URL(request.url);\n',
    '  if (request.method === "GET" && careDoseMatch) {\n'
    '    await authorizationStore.requirePersonFeature(\n'
    '      identity.appUserId,\n'
    '      careDoseMatch[1],\n'
    '      "treatment.adherence.read",\n'
    '      "care.basic",\n'
    '    );\n'
    '    const url = new URL(request.url);\n',
    "care dose authorization",
)

text = replace_once(
    text,
    '  if (request.method === "GET" && careEventMatch) {\n    const url = new URL(request.url);\n',
    '  if (request.method === "GET" && careEventMatch) {\n'
    '    await authorizationStore.requirePersonFeature(\n'
    '      identity.appUserId,\n'
    '      careEventMatch[1],\n'
    '      "care.events.read",\n'
    '      "care.basic",\n'
    '    );\n'
    '    const url = new URL(request.url);\n',
    "care event authorization",
)

text = replace_once(
    text,
    '  if (request.method === "GET" && careWomenCalendarMatch) {\n    requireWomenCalendarPilot();\n',
    '  if (request.method === "GET" && careWomenCalendarMatch) {\n'
    '    requireWomenCalendarPilot();\n'
    '    await authorizationStore.requirePersonFeature(\n'
    '      identity.appUserId,\n'
    '      careWomenCalendarMatch[1],\n'
    '      "women_health.summary.read",\n'
    '      "care.basic",\n'
    '    );\n',
    "women summary authorization",
)

text = replace_once(
    text,
    '  if (request.method === "POST" && careWomenSupportMatch) {\n    requireWomenCalendarPilot();\n',
    '  if (request.method === "POST" && careWomenSupportMatch) {\n'
    '    requireWomenCalendarPilot();\n'
    '    await authorizationStore.requirePersonFeature(\n'
    '      identity.appUserId,\n'
    '      careWomenSupportMatch[1],\n'
    '      "women_health.support.write",\n'
    '      "care.basic",\n'
    '    );\n',
    "women support authorization",
)

text = replace_once(
    text,
    'async function authenticate(request: Request): Promise<AuthUser> {\n',
    'async function authenticate(request: Request): Promise<AuthenticatedUser> {\n',
    "authenticate return type",
)

text = replace_once(
    text,
    '    userMetadata: value.user_metadata && typeof value.user_metadata === "object"\n      ? value.user_metadata\n      : {},\n  };\n',
    '    userMetadata: value.user_metadata && typeof value.user_metadata === "object"\n'
    '      ? value.user_metadata\n'
    '      : {},\n'
    '    identities: Array.isArray(value.identities)\n'
    '      ? value.identities as ProviderIdentity[]\n'
    '      : [],\n'
    '  };\n',
    "authenticate identities",
)

path.write_text(text, encoding="utf-8")
print("ecosystem runtime router codemod applied")
