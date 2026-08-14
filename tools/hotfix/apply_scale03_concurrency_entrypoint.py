from pathlib import Path

path = Path("supabase/functions/lifemate-api/index.ts")
text = path.read_text(encoding="utf-8")

replacements = [
    (
        'import { createRequestRateLimiterFromEnvironment } from "./rate_limit.ts";\nimport { enforceRateLimit } from "./security.ts";',
        'import { createRequestRateLimiterFromEnvironment } from "./rate_limit.ts";\nimport { createRequestConcurrencyGateFromEnvironment } from "./concurrency.ts";\nimport { enforceRateLimit } from "./security.ts";',
    ),
    (
        'const requestRateLimiter = createRequestRateLimiterFromEnvironment();\n\nDeno.serve(async (request: Request) => {',
        'const requestRateLimiter = createRequestRateLimiterFromEnvironment();\nconst requestConcurrency = createRequestConcurrencyGateFromEnvironment();\n\nDeno.serve(async (request: Request) => {',
    ),
    (
        '  try {\n    const auth = await authenticate(request);\n    await requestRateLimiter.enforce(request.method, path, auth.id);\n    return await route(request, path, auth);\n  } catch (error) {',
        '  let concurrencyLease;\n  try {\n    concurrencyLease = requestConcurrency.acquire(request.method, path);\n    const auth = await authenticate(request);\n    await requestRateLimiter.enforce(request.method, path, auth.id);\n    return await route(request, path, auth);\n  } catch (error) {',
    ),
    (
        '    return problem(\n      500,\n      "internal_error",\n      "The request could not be completed.",\n      correlationId,\n    );\n  }\n});',
        '    return problem(\n      500,\n      "internal_error",\n      "The request could not be completed.",\n      correlationId,\n    );\n  } finally {\n    concurrencyLease?.release();\n  }\n});',
    ),
]

for before, after in replacements:
    count = text.count(before)
    if count != 1:
        raise SystemExit(f"expected exactly one patch target, found {count}: {before[:90]!r}")
    text = text.replace(before, after, 1)

path.write_text(text, encoding="utf-8")
