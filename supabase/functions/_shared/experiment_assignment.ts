export type WeightedExperimentVariant<T = unknown> = {
  key: string;
  weightBasisPoints: number;
  controlValue: T;
  version: number;
};

export async function stableExperimentBucket(
  experimentKey: string,
  subjectKey: string,
): Promise<number> {
  const bytes = new TextEncoder().encode(`experiment:${experimentKey}:${subjectKey}`);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return (
    (((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) >>> 0) %
    10_000
  );
}

export function selectWeightedExperimentVariant<T>(
  variants: readonly WeightedExperimentVariant<T>[],
  bucketBasisPoints: number,
): WeightedExperimentVariant<T> | null {
  let ceiling = 0;
  for (const variant of variants) {
    ceiling += variant.weightBasisPoints;
    if (bucketBasisPoints < ceiling) return variant;
  }
  return null;
}
