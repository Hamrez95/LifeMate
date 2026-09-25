import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { buildOperationsSnapshot } from "./operations_snapshot.ts";
import { createAdminStore } from "./store.ts";

const OPERATIONS_SNAPSHOT_PATH = "/api/v1/operations/snapshot";

export function createOperationsSnapshotRouteHandler(databaseUrl: string) {
  const store = createAdminStore(databaseUrl);

  return async function operationsSnapshotRouteHandler(input: {
    request: Request;
    path: string;
    admin: AdminCapabilitySnapshot;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, admin, origin } = input;
    if (request.method !== "GET" || path !== OPERATIONS_SNAPSHOT_PATH) {
      return null;
    }

    requirePermission(admin, "operations.read");
    const snapshot = await buildOperationsSnapshot({
      checkDatabase: () => store.health(),
    });
    return json(snapshot, 200, origin);
  };
}
