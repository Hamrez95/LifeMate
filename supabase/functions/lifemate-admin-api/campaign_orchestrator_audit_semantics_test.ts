function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("campaign second confirmation does not masquerade as elevated health access", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827043400_campaign_confirmation_audit_semantics.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.includes("'marketing.campaign.confirm'") &&
      migration.includes("p_correlation_id,false"),
    "campaign confirmation audit must record elevated_access=false",
  );
  assert(
    !migration.includes("p_correlation_id,true"),
    "campaign confirmation must never be classified as elevated access",
  );
});
