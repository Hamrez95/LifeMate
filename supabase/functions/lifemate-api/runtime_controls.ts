import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export const newUserOnboardingControlKey = "new_user_onboarding";

export type RuntimeControlStore = {
  requireNewUserOnboardingEnabled(): Promise<void>;
};

export function createRuntimeControlStore(
  databaseUrl: string,
): RuntimeControlStore {
  const sql = getLifeMateSql(databaseUrl);

  return {
    async requireNewUserOnboardingEnabled(): Promise<void> {
      try {
        const rows = await sql<{ enabled: boolean }[]>`
          select enabled
          from security.runtime_controls
          where control_key = ${newUserOnboardingControlKey}
          limit 1
        `;

        if (rows.length !== 1 || rows[0]?.enabled !== true) {
          throw new ApiError(
            503,
            "onboarding_paused",
            "New user onboarding is temporarily paused.",
          );
        }
      } catch (error) {
        if (error instanceof ApiError) throw error;
        throw new ApiError(
          503,
          "onboarding_control_unavailable",
          "New user onboarding is temporarily unavailable.",
        );
      }
    },
  };
}
