import {
  BCB_ATTRIBUTION,
  BCB_SOURCE,
  EconomicSeriesError,
  normalizeUtcTimestamp,
  ORIGINAL_SOURCE,
  parseReadRequest,
  SERIES_LICENSE,
  staleDays,
} from "../_shared/economic_series.ts";
import {
  readObservations,
  seriesSettings,
  seriesState,
} from "../_shared/economic_series_store.ts";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type",
  "access-control-expose-headers": "Link",
};
let readMinute = -1;
let readsThisMinute = 0;
const MAX_READS_PER_MINUTE_PER_INSTANCE = 300;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  // The gateway accepts a valid user JWT or project publishable credential.
  // This public cache response does not require a user identity.
  if (!/^Bearer\s+\S+$/i.test(request.headers.get("authorization") ?? "")) {
    return json({ error: "unauthorized" }, 401);
  }
  if (Deno.env.get("ECONOMIC_SERIES_READ_ENABLED") !== "true") {
    return json({ error: "feature_disabled" }, 503);
  }
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const input = parseReadRequest(payload);
  if (!input) return json({ error: "invalid_series_request" }, 400);
  if (!allowRead()) return json({ error: "rate_limited" }, 429);
  try {
    const [setting] = await seriesSettings(input.code);
    if (!setting?.redistribution_allowed) {
      return json({ error: "license_pending" }, 503);
    }
    const [observations, state] = await Promise.all([
      readObservations(input.code, input.from, input.through),
      seriesState(input.code),
    ]);
    const today = new Date().toISOString().slice(0, 10);
    const license = SERIES_LICENSE[input.code];
    return json(
      {
        code: input.code,
        unit: setting.unit,
        source: BCB_SOURCE,
        attribution: BCB_ATTRIBUTION,
        ...(license ?? {}),
        original_source: ORIGINAL_SOURCE[input.code] ?? null,
        source_url:
          `https://www3.bcb.gov.br/sgspub/consultarvalores/consultarValoresSeries.do?method=consultarGraficoPorId&hdOidSeriesSelecionadas=${input.code}`,
        observations: observations.map((row) => ({
          ...row,
          fetched_at: normalizeUtcTimestamp(row.fetched_at),
        })),
        latest_reference_start: state.last_reference_start,
        latest_reference_end: state.last_reference_end,
        stale_days: staleDays(state.last_reference_start, today),
        last_success_at: state.last_success_at
          ? normalizeUtcTimestamp(state.last_success_at)
          : null,
        last_error_code: state.last_error_code,
      },
      200,
      license ? { Link: `<${license.license_url}>; rel="license"` } : {},
    );
  } catch (error) {
    return json({
      error: error instanceof EconomicSeriesError
        ? error.code
        : "database_unavailable",
    }, 503);
  }
});

function allowRead(): boolean {
  const minute = Math.floor(Date.now() / 60_000);
  if (minute !== readMinute) {
    readMinute = minute;
    readsThisMinute = 0;
  }
  if (readsThisMinute >= MAX_READS_PER_MINUTE_PER_INSTANCE) return false;
  readsThisMinute += 1;
  return true;
}

function json(
  value: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...cors, "content-type": "application/json", ...headers },
  });
}
