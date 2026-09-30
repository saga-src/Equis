import {
  collectSeries,
  EconomicSeriesError,
  fetchSgsPage,
  SERIES,
  SERIES_CODES,
  shouldSeedRecent,
} from "../_shared/economic_series.ts";
import {
  claimSeries,
  completeSeries,
  failSeries,
  seriesSettings,
  seriesState,
  upsertObservations,
} from "../_shared/economic_series_store.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const secret = Deno.env.get("ECONOMIC_SERIES_SYNC_SECRET") ?? "";
  const supplied = request.headers.get("x-equis-sync-secret") ?? "";
  if (!secret || !(await secretsEqual(secret, supplied))) {
    return json({ error: "unauthorized" }, 401);
  }
  if (Deno.env.get("ECONOMIC_SERIES_COLLECTION_ENABLED") !== "true") {
    return json({ operation: "collect", disabled: true, results: [] });
  }
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (
    !payload || typeof payload !== "object" || Array.isArray(payload) ||
    Object.keys(payload).length !== 1 ||
    (payload as Record<string, unknown>).operation !== "collect"
  ) {
    return json({ error: "invalid_collection_request" }, 400);
  }

  try {
    const settings = await seriesSettings();
    const today = new Date().toISOString().slice(0, 10);
    const results = [];
    for (const code of SERIES_CODES) {
      const setting = settings.find((entry) => entry.code === code);
      if (!setting?.persistence_allowed) continue;
      if (setting.unit !== SERIES[code]) {
        results.push({
          code,
          status: "failed",
          error_code: "series_unit_mismatch",
        });
        continue;
      }
      const checkpoint = await seriesState(code);
      const seedRecent = shouldSeedRecent(checkpoint.recent_seeded_at, today);
      if (
        checkpoint.next_from > today && !seedRecent
      ) {
        results.push({ code, status: "current" });
        continue;
      }
      const state = await claimSeries(code);
      if (!state?.lease_token) {
        results.push({ code, status: "leased" });
        continue;
      }
      results.push(
        await collectSeries(
          code,
          {
            next_from: state.next_from,
            last_reference_start: state.last_reference_start,
            last_reference_end: state.last_reference_end,
            lease_token: state.lease_token,
          },
          today,
          {
            fetchPage: fetchSgsPage,
            upsert: upsertObservations,
            complete: completeSeries,
            fail: failSeries,
          },
          seedRecent,
        ),
      );
    }
    return json({ operation: "collect", results });
  } catch (error) {
    return json({
      error: error instanceof EconomicSeriesError
        ? error.code
        : "collection_failed",
    }, 503);
  }
});

async function secretsEqual(
  expected: string,
  supplied: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
    crypto.subtle.digest("SHA-256", encoder.encode(supplied)),
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}
