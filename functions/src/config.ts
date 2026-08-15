/**
 * Deployment region.
 *
 * Same region as Firestore, so a function doesn't pay a cross-region round trip
 * on every read — for the aggregation job that would be most of its runtime.
 *
 * Passed explicitly to every function rather than through `setGlobalOptions`.
 * Global options are applied when index.ts executes, but TypeScript hoists the
 * `import`/`export … from` requires above it, so each function is already
 * defined — with whatever the default region was — before the global option is
 * ever set. The first deploy proved it: the functions landed in two different
 * regions depending on module load order.
 */
export const REGION = 'me-central1';

/**
 * v1 Auth triggers only run in us-central1 — there is no choice to make.
 */
export const AUTH_TRIGGER_REGION = 'us-central1';
