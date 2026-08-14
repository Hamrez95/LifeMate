from pathlib import Path

# One-shot deterministic source transformation for Scale-02. The helper and
# workflow are removed from the feature branch after the generated patch lands.
path = Path("supabase/functions/lifemate-api/index.ts")
text = path.read_text(encoding="utf-8")

replacements = [
    (
        'import { loadRuntimeConfig } from "./runtime_config.ts";\nimport { enforceRateLimit } from "./security.ts";',
        'import { loadRuntimeConfig } from "./runtime_config.ts";\nimport { createRequestRateLimiterFromEnvironment } from "./rate_limit.ts";\nimport { enforceRateLimit } from "./security.ts";',
    ),
    (
        'const womenCalendarPilotEnabled =\n  (Deno.env.get("ENABLE_WOMEN_CALENDAR_PILOT") ?? "true").toLowerCase() !==\n    "false";\n\nDeno.serve(async (request: Request) => {',
        'const womenCalendarPilotEnabled =\n  (Deno.env.get("ENABLE_WOMEN_CALENDAR_PILOT") ?? "true").toLowerCase() !==\n    "false";\nconst requestRateLimiter = createRequestRateLimiterFromEnvironment();\n\nDeno.serve(async (request: Request) => {',
    ),
    (
        '  try {\n    const auth = await authenticate(request);\n    return await route(request, path, auth);',
        '  try {\n    const auth = await authenticate(request);\n    await requestRateLimiter.enforce(request.method, path, auth.id);\n    return await route(request, path, auth);',
    ),
]

for before, after in replacements:
    count = text.count(before)
    if count != 1:
        raise SystemExit(f"expected exactly one patch target, found {count}: {before[:80]!r}")
    text = text.replace(before, after, 1)

path.write_text(text, encoding="utf-8")
