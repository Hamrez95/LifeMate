import {
  createCareRequestStore as createEmailCareRequestStore,
} from "./care_requests_email.ts";
import { createPhoneCareRequestStore } from "./phone_care_requests.ts";
import { ApiError } from "./validation.ts";

type CareRequestIdentity = {
  appUserId: string;
  auth: { email: string | null };
};

export function createCareRequestStore(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const email = createEmailCareRequestStore(databaseUrl, contactHashingSecret);
  const phone = createPhoneCareRequestStore(databaseUrl, contactHashingSecret);

  async function create(
    identity: CareRequestIdentity,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const contactType = String(body.contactType ?? "email").trim()
      .toLowerCase();
    if (contactType === "phone") return await phone.create(identity, body);
    if (contactType !== "email") {
      throw new ApiError(
        400,
        "invalid_care_request_contact_type",
        "Care request contact type is invalid.",
      );
    }
    return await email.create(identity, body);
  }

  async function listOutgoing(
    caregiverUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const emailRows = await email.listOutgoing(caregiverUserId);
    const phoneRows = await phone.listOutgoing(caregiverUserId);
    return sortNewest([...emailRows, ...phoneRows]);
  }

  async function listIncoming(
    identity: CareRequestIdentity,
  ): Promise<Record<string, unknown>[]> {
    const emailRows = await email.listIncoming(identity);
    const phoneRows = await phone.listIncoming(identity);
    return sortNewest([...emailRows, ...phoneRows]);
  }

  async function respond(
    identity: CareRequestIdentity,
    requestId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const phoneResult = await phone.respondIfPhone(identity, requestId, body);
    if (phoneResult) return phoneResult;
    return await email.respond(identity, requestId, body);
  }

  async function cancel(
    caregiverUserId: string,
    requestId: string,
  ): Promise<void> {
    if (await phone.cancelIfPhone(caregiverUserId, requestId)) return;
    await email.cancel(caregiverUserId, requestId);
  }

  return { create, listOutgoing, listIncoming, respond, cancel };
}

function sortNewest(
  rows: Record<string, unknown>[],
): Record<string, unknown>[] {
  return rows.sort((left, right) =>
    String(right.createdAtUtc ?? "").localeCompare(
      String(left.createdAtUtc ?? ""),
    )
  );
}
