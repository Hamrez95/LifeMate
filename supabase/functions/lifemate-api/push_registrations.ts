import {
  encryptMessagingToken,
  hashMessagingToken,
  readMessagingTokenKey,
} from "../_shared/messaging_token_crypto.ts";
import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const productPattern = /^[a-z0-9][a-z0-9_.:-]{0,63}$/;
const providerPattern = /^[a-z0-9][a-z0-9_.-]{1,39}$/;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function required(value: unknown, field: string, max: number): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "push_registration_invalid",
      `${field} is invalid.`,
    );
  }
  const next = value.trim();
  if (!next || new TextEncoder().encode(next).byteLength > max) {
    throw new ApiError(
      400,
      "push_registration_invalid",
      `${field} is invalid.`,
    );
  }
  return next;
}

export function parsePushRegistration(body: Record<string, unknown>) {
  const productCode = required(body.productCode, "productCode", 64)
    .toLowerCase();
  const provider = required(body.provider, "provider", 40).toLowerCase();
  const platform = required(body.platform, "platform", 16);
  const token = required(body.token, "token", 4096);
  if (
    !productPattern.test(productCode) || !providerPattern.test(provider) ||
    !["Android", "iOS", "Web"].includes(platform) || token.length < 20
  ) {
    throw new ApiError(
      400,
      "push_registration_invalid",
      "Push registration is invalid.",
    );
  }
  return { productCode, provider, platform, token };
}

function result(result: Record<string, unknown>): Record<string, unknown> {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "push_registration_unavailable",
      "Push registration workflow returned an invalid result.",
    );
  }
  if (status >= 400) {
    throw new ApiError(
      status,
      String(result.code ?? "push_registration_unavailable"),
      typeof result.message === "string"
        ? result.message
        : "Push registration could not be completed.",
    );
  }
  return result;
}

export function createPushRegistrationStore(
  databaseUrl: string,
  hashingSecret = Deno.env.get("LIFEMATE_MESSAGING_TOKEN_HASHING_SECRET") ?? "",
) {
  const sql = getLifeMateSql(databaseUrl);

  return {
    async upsert(appUserId: string, body: Record<string, unknown>) {
      const payload = parsePushRegistration(body);
      const accountRows = await sql`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text as account_id
      `;
      const accountId = String(accountRows[0]?.account_id ?? "");
      if (!uuidPattern.test(accountId)) {
        throw new ApiError(
          409,
          "identity_account_mapping_missing",
          "Account mapping is unavailable.",
        );
      }
      try {
        const key = readMessagingTokenKey();
        const tokenHash = await hashMessagingToken(
          hashingSecret,
          payload.token,
        );
        const envelope = await encryptMessagingToken(key, {
          accountId,
          productCode: payload.productCode,
          provider: payload.provider,
          tokenHash,
        }, payload.token);
        const rows = await sql`
          select messaging.upsert_push_registration(
            ${appUserId}::uuid,${payload.productCode}::varchar,${payload.platform}::varchar,
            ${payload.provider}::varchar,${tokenHash}::varchar,${envelope.ciphertextB64}::text,
            ${envelope.nonceB64}::varchar,${envelope.keyVersion}::smallint
          ) as result
        `;
        return result(rows[0]?.result ?? {});
      } catch (error) {
        if (error instanceof ApiError) throw error;
        throw new ApiError(
          503,
          "push_registration_unavailable",
          "Push registration security configuration is unavailable.",
        );
      }
    },

    async revoke(appUserId: string, registrationId: string) {
      if (!uuidPattern.test(registrationId)) {
        throw new ApiError(
          400,
          "push_registration_invalid",
          "registrationId is invalid.",
        );
      }
      const rows = await sql`
        select messaging.revoke_push_registration(${appUserId}::uuid,${registrationId}::uuid) as result
      `;
      return result(rows[0]?.result ?? {});
    },
  };
}
