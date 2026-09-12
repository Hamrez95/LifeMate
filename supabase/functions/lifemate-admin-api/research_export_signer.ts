import { ApiError } from "./validation.ts";

export function createResearchExportSignerFromEnvironment(
  fetcher: typeof fetch = fetch,
) {
  const url = (Deno.env.get("LIFEMATE_RESEARCH_EXPORT_SIGNER_URL") ?? "")
    .trim();
  const token = (Deno.env.get("LIFEMATE_RESEARCH_EXPORT_SIGNER_TOKEN") ?? "")
    .trim();
  if (!url || !token || token.length < 32 || !/^https:\/\//i.test(url)) {
    return undefined;
  }

  return {
    async sign(actorAccountId: string, jobId: string) {
      try {
        const response = await fetcher(url, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-lifemate-research-signer-token": token,
          },
          body: JSON.stringify({ actorAccountId, jobId }),
          signal: AbortSignal.timeout(5000),
        });
        if (response.status === 404) {
          throw new ApiError(
            404,
            "research_export_download_unavailable",
            "Research export is unavailable or expired.",
          );
        }
        if (!response.ok) {
          throw new ApiError(
            503,
            "research_export_signer_unavailable",
            "Research export download is temporarily unavailable.",
          );
        }
        const payload = await response.json().catch(() => null) as
          | Record<string, unknown>
          | null;
        if (
          typeof payload?.signedUrl !== "string" ||
          !/^https:\/\//i.test(payload.signedUrl) ||
          payload.expiresInSeconds !== 600
        ) {
          throw new ApiError(
            503,
            "research_export_signer_invalid",
            "Research export signer returned an invalid response.",
          );
        }
        return {
          signedUrl: payload.signedUrl,
          expiresInSeconds: 600,
        };
      } catch (error) {
        if (error instanceof ApiError) throw error;
        throw new ApiError(
          503,
          "research_export_signer_unavailable",
          "Research export download is temporarily unavailable.",
        );
      }
    },
  };
}
