import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  canonicalSegmentRuleSet,
  hashSegmentRuleSet,
  parseSegmentRuleSet,
  type SegmentRuleSet,
} from "./audience_segments.ts";
import { createAudienceSegmentStore } from "./audience_segments_service.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type RouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

type SegmentWritePayload = {
  key?: string;
  name: string;
  description: string | null;
  ruleSet: SegmentRuleSet;
  expectedVersion?: number;
  status?: "Active" | "Archived";
};

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const KEY = /^[a-z][a-z0-9._-]{2,95}$/;
const MIN_PREVIEW_COHORT = 10;

function segmentIdFromPath(path: string): string | null {
  const match = path.match(/^\/api\/v1\/marketing\/segments\/([^/]+)$/);
  if (!match) return null;
  const id = decodeURIComponent(match[1]);
  if (!UUID.test(id)) {
    throw new ApiError(
      400,
      "segment_id_invalid",
      "Audience segment id is invalid.",
    );
  }
  return id;
}

function segmentActionId(
  path: string,
  action: "preview" | "snapshot",
): string | null {
  const match = path.match(
    new RegExp(`^\\/api\\/v1\\/marketing\\/segments\\/([^/]+)\\/${action}$`),
  );
  if (!match) return null;
  const id = decodeURIComponent(match[1]);
  if (!UUID.test(id)) {
    throw new ApiError(
      400,
      "segment_id_invalid",
      "Audience segment id is invalid.",
    );
  }
  return id;
}

function boundedText(
  value: unknown,
  field: string,
  max: number,
  required: boolean,
): string | null {
  if (value == null) {
    if (required) {
      throw new ApiError(
        400,
        "segment_payload_invalid",
        `${field} is required.`,
      );
    }
    return null;
  }
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "segment_payload_invalid",
      `${field} must be text.`,
    );
  }
  const text = value.trim();
  if (required && text.length < 2) {
    throw new ApiError(
      400,
      "segment_payload_invalid",
      `${field} is too short.`,
    );
  }
  if (text.length > max) {
    throw new ApiError(400, "segment_payload_invalid", `${field} is too long.`);
  }
  return text || null;
}

async function parseWritePayload(
  request: Request,
  creating: boolean,
): Promise<SegmentWritePayload> {
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(
      400,
      "segment_payload_invalid",
      "Audience segment payload must be an object.",
    );
  }
  const raw = body as Record<string, unknown>;
  let key: string | undefined;
  if (creating) {
    if (
      typeof raw.key !== "string" || !KEY.test(raw.key.trim().toLowerCase())
    ) {
      throw new ApiError(
        400,
        "segment_key_invalid",
        "Audience segment key is invalid.",
      );
    }
    key = raw.key.trim().toLowerCase();
  }
  const name = boundedText(raw.name, "name", 120, true)!;
  const description = boundedText(raw.description, "description", 500, false);
  const ruleSet = parseSegmentRuleSet(raw.rules);
  if (!creating) {
    if (
      !Number.isInteger(raw.expectedVersion) || Number(raw.expectedVersion) < 1
    ) {
      throw new ApiError(
        400,
        "segment_version_invalid",
        "expectedVersion must be a positive integer.",
      );
    }
    if (raw.status !== "Active" && raw.status !== "Archived") {
      throw new ApiError(
        400,
        "segment_status_invalid",
        "status must be Active or Archived.",
      );
    }
  }
  return {
    key,
    name,
    description,
    ruleSet,
    expectedVersion: creating ? undefined : Number(raw.expectedVersion),
    status: creating ? undefined : raw.status as "Active" | "Archived",
  };
}

async function parseSnapshotExpectedVersion(request: Request): Promise<number> {
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(
      400,
      "segment_snapshot_payload_invalid",
      "Snapshot payload must be an object.",
    );
  }
  const expectedVersion = (body as Record<string, unknown>).expectedVersion;
  if (!Number.isInteger(expectedVersion) || Number(expectedVersion) < 1) {
    throw new ApiError(
      400,
      "segment_version_invalid",
      "expectedVersion must be a positive integer.",
    );
  }
  return Number(expectedVersion);
}

async function hashWritePayload(payload: SegmentWritePayload): Promise<string> {
  const canonical = JSON.stringify({
    key: payload.key ?? null,
    name: payload.name,
    description: payload.description,
    rules: JSON.parse(canonicalSegmentRuleSet(payload.ruleSet)),
    expectedVersion: payload.expectedVersion ?? null,
    status: payload.status ?? null,
  });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return Array.from(new Uint8Array(digest)).map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

async function hashSnapshotRequest(
  id: string,
  expectedVersion: number,
  key: string,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${id}:${expectedVersion}:${key}`),
  );
  return Array.from(new Uint8Array(digest)).map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

export function createAudienceSegmentRouteHandler(databaseUrl: string) {
  const store = createAudienceSegmentStore(databaseUrl);

  return async function handleAudienceSegmentRoute(
    context: RouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (
      request.method === "GET" &&
      path === "/api/v1/marketing/segments/capabilities"
    ) {
      requirePermission(admin, "marketing.segment.read");
      return json(store.sourceCapabilities(), 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/marketing/segments") {
      requirePermission(admin, "marketing.segment.read");
      const items = await store.list();
      return json(
        {
          items,
          total: items.length,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST" && path === "/api/v1/marketing/segments") {
      requirePermission(admin, "marketing.segment.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseWritePayload(request, true);
      const ruleHash = await hashSegmentRuleSet(payload.ruleSet);
      const segment = await store.create({
        actorAccountId: accountId,
        key: payload.key!,
        name: payload.name,
        description: payload.description,
        ruleSet: payload.ruleSet,
        ruleHash,
        idempotencyKey,
        requestHash: await hashWritePayload(payload),
        correlationId,
      });
      return json(segment, 201, origin);
    }

    const previewId = segmentActionId(path, "preview");
    if (request.method === "GET" && previewId) {
      requirePermission(admin, "marketing.segment.read");
      return json(await store.preview(previewId), 200, origin);
    }

    const snapshotId = segmentActionId(path, "snapshot");
    if (request.method === "POST" && snapshotId) {
      requirePermission(admin, "marketing.segment.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const expectedVersion = await parseSnapshotExpectedVersion(request);
      const snapshot = await store.snapshot({
        actorAccountId: accountId,
        id: snapshotId,
        expectedVersion,
        idempotencyKey,
        requestHash: await hashSnapshotRequest(
          snapshotId,
          expectedVersion,
          idempotencyKey,
        ),
        correlationId,
      });
      const exactCount = Number(snapshot.memberCount);
      const suppressed = exactCount > 0 && exactCount < MIN_PREVIEW_COHORT;
      return json(
        {
          ...snapshot,
          memberCount: suppressed ? null : exactCount,
          suppressed,
          minimumCohortSize: MIN_PREVIEW_COHORT,
        },
        201,
        origin,
      );
    }

    const id = segmentIdFromPath(path);
    if (request.method === "GET" && id) {
      requirePermission(admin, "marketing.segment.read");
      return json(await store.get(id), 200, origin);
    }
    if (request.method === "PUT" && id) {
      requirePermission(admin, "marketing.segment.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseWritePayload(request, false);
      const segment = await store.update({
        actorAccountId: accountId,
        id,
        expectedVersion: payload.expectedVersion!,
        name: payload.name,
        description: payload.description,
        ruleSet: payload.ruleSet,
        ruleHash: await hashSegmentRuleSet(payload.ruleSet),
        status: payload.status!,
        idempotencyKey,
        requestHash: await hashWritePayload(payload),
        correlationId,
      });
      return json(segment, 200, origin);
    }

    return null;
  };
}
