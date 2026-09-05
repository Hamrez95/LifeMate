import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { hashContactPoint } from "../_shared/contact_point_crypto.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createGrowthStore } from "./growth.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for growth integration tests.",
  );
}

const contactSecret = "integration-growth-contact-secret-32-bytes-minimum";

Deno.test({
  name: "growth workflows are private, replay-safe and reject self-attribution",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const growth = createGrowthStore(databaseUrl, contactSecret);
    const suffix = crypto.randomUUID();

    const referrerAuth = auth(
      `growth-referrer-${suffix}`,
      `growth-referrer-${suffix}@example.test`,
      "+989121230201",
    );
    const referredAuth = auth(
      `growth-referred-${suffix}`,
      `growth-referred-${suffix}@example.test`,
      "+989121230202",
    );
    const alternateAuth = auth(
      `growth-alternate-${suffix}`,
      `growth-alternate-${suffix}@example.test`,
      "+989121230203",
    );

    try {
      const referrer = await bootstrap(db, referrerAuth, "Growth Referrer");
      const referred = await bootstrap(db, referredAuth, "Growth Referred");
      const alternate = await bootstrap(db, alternateAuth, "Growth Alternate");

      const referrerCode = await growth.ensureReferralCode(referrer.appUserId);
      const alternateCode = await growth.ensureReferralCode(
        alternate.appUserId,
      );
      assert(/^[A-Z0-9]{8,32}$/.test(String(referrerCode.code)));
      assert(/^[A-Z0-9]{8,32}$/.test(String(alternateCode.code)));

      await expectApiError(
        () =>
          growth.attributeReferral({
            appUserId: referrer.appUserId,
            body: { code: referrerCode.code },
            idempotencyKey: "growth-self-referral-0001",
          }),
        404,
        "referral_code_not_eligible",
      );

      const referralKey = "growth-referral-replay-0001";
      const [firstAttribution, concurrentReplay] = await Promise.all([
        growth.attributeReferral({
          appUserId: referred.appUserId,
          body: { code: referrerCode.code },
          idempotencyKey: referralKey,
        }),
        growth.attributeReferral({
          appUserId: referred.appUserId,
          body: { code: referrerCode.code },
          idempotencyKey: referralKey,
        }),
      ]);
      assertEquals(
        firstAttribution.attributionId,
        concurrentReplay.attributionId,
      );
      assert(
        firstAttribution.replayed === true ||
          concurrentReplay.replayed === true,
        "one concurrent referral call must become a replay",
      );

      await expectApiError(
        () =>
          growth.attributeReferral({
            appUserId: referred.appUserId,
            body: { code: alternateCode.code },
            idempotencyKey: referralKey,
          }),
        409,
        "idempotency_conflict",
      );

      const advocacyKey = "growth-advocacy-replay-0001";
      const advocacyBody = {
        platformCode: "instagram",
        evidenceType: "PostUrl",
        evidenceReference: `https://example.invalid/advocacy/${suffix}`,
      };
      const advocacy = await growth.submitAdvocacy({
        appUserId: referred.appUserId,
        body: advocacyBody,
        idempotencyKey: advocacyKey,
      });
      const advocacyReplay = await growth.submitAdvocacy({
        appUserId: referred.appUserId,
        body: advocacyBody,
        idempotencyKey: advocacyKey,
      });
      assertEquals(advocacyReplay.submissionId, advocacy.submissionId);
      assertEquals(advocacyReplay.replayed, true);

      await expectApiError(
        () =>
          growth.submitAdvocacy({
            appUserId: referred.appUserId,
            body: {
              ...advocacyBody,
              evidenceReference:
                `https://example.invalid/advocacy/${suffix}/changed`,
            },
            idempotencyKey: advocacyKey,
          }),
        409,
        "idempotency_conflict",
      );

      const accountRows = await sql`
        select identity.account_id_for_legacy_app_user(${referrer.appUserId}::uuid)::text as account_id
      `;
      const referrerAccountId = String(accountRows[0]?.account_id ?? "");
      assert(referrerAccountId.length > 0);
      const phoneHash = await hashContactPoint(
        contactSecret,
        "Phone",
        referrerAuth.phone!,
      );
      await sql`
        insert into identity.contact_points(
          account_id,kind,normalized_value_hash,status,verified_at_utc
        ) values(
          ${referrerAccountId}::uuid,'Phone',${phoneHash},'Verified',now()
        )
        on conflict do nothing
      `;

      await expectApiError(
        () =>
          growth.createGift({
            appUserId: referrer.appUserId,
            body: {
              recipientPhone: referrerAuth.phone,
              targetKind: "Offer",
              targetId: crypto.randomUUID(),
            },
            idempotencyKey: "growth-self-gift-0001",
          }),
        404,
        "gift_recipient_not_eligible",
      );

      const userRows = await sql`select current_user as current_user`;
      if (String(userRows[0]?.current_user) === "lifemate_edge_runtime") {
        await assertRejects(
          () =>
            sql`
              insert into growth.advocacy_submissions(
                account_id,platform_code,evidence_type,evidence_source,
                evidence_reference_hash,status
              ) values(
                ${referrerAccountId}::uuid,'test','Other','UserSubmission',
                ${"a".repeat(64)},'PendingReview'
              )
            `,
        );
      }
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await sql.end({ timeout: 5 }).catch(() => undefined);
    }
  },
});

function auth(subject: string, email: string, phone: string): AuthUser {
  return { id: subject, email, phone, userMetadata: {} };
}

async function bootstrap(
  db: ReturnType<typeof createLifeMateDatabase>,
  authUser: AuthUser,
  displayName: string,
) {
  await db.bootstrapUser(authUser, {
    displayName,
    locale: "fa",
    timeZone: "Asia/Tehran",
  });
  return await db.requireIdentity(authUser);
}

async function expectApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  try {
    await action();
  } catch (error) {
    if (!(error instanceof ApiError)) throw error;
    assertEquals(error.status, status);
    assertEquals(error.code, code);
    return;
  }
  throw new Error(`Expected ApiError ${status}/${code}.`);
}
