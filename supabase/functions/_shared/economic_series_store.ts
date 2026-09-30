import {
  BCB_SOURCE,
  type EconomicObservation,
  EconomicSeriesError,
  type SeriesCode,
  type SeriesUnit,
} from "./economic_series.ts";

export type SeriesSettings = {
  code: SeriesCode;
  unit: SeriesUnit;
  persistence_allowed: boolean;
  redistribution_allowed: boolean;
};

export type SeriesState = {
  code: SeriesCode;
  next_from: string;
  last_success_at: string | null;
  recent_seeded_at: string | null;
  last_error_code: string | null;
  last_reference_start: string | null;
  last_reference_end: string | null;
  lease_token: string | null;
};

const SETTINGS = "economic_series_settings";
const OBSERVATIONS = "economic_series_observations";
const STATE = "economic_series_collection_state";

export async function seriesSettings(
  code?: SeriesCode,
): Promise<SeriesSettings[]> {
  const query = new URLSearchParams({
    select: "code,unit,persistence_allowed,redistribution_allowed",
    order: "code.asc",
  });
  if (code !== undefined) query.set("code", `eq.${code}`);
  return await dbGet<SeriesSettings[]>(SETTINGS, query);
}

export async function seriesState(code: SeriesCode): Promise<SeriesState> {
  const query = new URLSearchParams({
    select:
      "code,next_from,last_success_at,recent_seeded_at,last_error_code,last_reference_start,last_reference_end,lease_token",
    code: `eq.${code}`,
    limit: "1",
  });
  const rows = await dbGet<SeriesState[]>(STATE, query);
  if (rows.length !== 1) {
    throw new EconomicSeriesError("series_state_missing", 500);
  }
  return rows[0];
}

export async function claimSeries(
  code: SeriesCode,
): Promise<SeriesState | null> {
  const token = crypto.randomUUID();
  const now = new Date();
  const leaseUntil = new Date(now.getTime() + 120_000).toISOString();
  const query = new URLSearchParams({
    code: `eq.${code}`,
    or: `(lease_until.is.null,lease_until.lt.${now.toISOString()})`,
    select:
      "code,next_from,last_success_at,recent_seeded_at,last_error_code,last_reference_start,last_reference_end,lease_token",
  });
  const rows = await dbRequest<SeriesState[]>(STATE, query, {
    method: "PATCH",
    headers: { prefer: "return=representation" },
    body: JSON.stringify({
      lease_token: token,
      lease_until: leaseUntil,
      last_attempt_at: now.toISOString(),
    }),
  });
  return rows[0] ?? null;
}

export async function upsertObservations(
  observations: EconomicObservation[],
): Promise<void> {
  if (observations.length === 0) return;
  const query = new URLSearchParams({ on_conflict: "code,reference_start" });
  await dbRequest(OBSERVATIONS, query, {
    method: "POST",
    headers: { prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify(observations),
  });
}

export async function completeSeries(
  code: SeriesCode,
  token: string,
  nextFrom: string,
  lastReferenceStart: string | null,
  lastReferenceEnd: string | null,
  count: number,
  seedRecent: boolean,
): Promise<void> {
  const completedAt = new Date().toISOString();
  await updateClaimed(code, token, {
    next_from: nextFrom,
    last_success_at: completedAt,
    ...(seedRecent ? { recent_seeded_at: completedAt } : {}),
    last_error_code: null,
    last_reference_start: lastReferenceStart,
    last_reference_end: lastReferenceEnd,
    last_observation_count: count,
    lease_token: null,
    lease_until: null,
  });
}

export async function failSeries(
  code: SeriesCode,
  token: string,
  errorCode: string,
): Promise<void> {
  await updateClaimed(code, token, {
    last_error_code: errorCode,
    lease_token: null,
    lease_until: null,
  });
}

export async function readObservations(
  code: SeriesCode,
  from: string,
  through: string,
): Promise<EconomicObservation[]> {
  return await dbRequest<EconomicObservation[]>(
    "rpc/read_economic_series",
    new URLSearchParams(),
    {
      method: "POST",
      body: JSON.stringify({ p_code: code, p_from: from, p_through: through }),
    },
  );
}

async function updateClaimed(
  code: SeriesCode,
  token: string,
  values: Record<string, unknown>,
): Promise<void> {
  const query = new URLSearchParams({
    code: `eq.${code}`,
    lease_token: `eq.${token}`,
    select: "code",
  });
  const rows = await dbRequest<Array<{ code: number }>>(STATE, query, {
    method: "PATCH",
    headers: { prefer: "return=representation" },
    body: JSON.stringify(values),
  });
  if (rows.length !== 1) {
    throw new EconomicSeriesError("series_lease_lost", 409);
  }
}

async function dbGet<T>(table: string, query: URLSearchParams): Promise<T> {
  return await dbRequest<T>(table, query, { method: "GET" });
}

async function dbRequest<T = unknown>(
  table: string,
  query: URLSearchParams,
  init: RequestInit,
): Promise<T> {
  const base = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) throw new EconomicSeriesError("database_unavailable", 503);
  const url = new URL(`/rest/v1/${table}`, base);
  url.search = query.toString();
  try {
    const response = await fetch(url, {
      ...init,
      headers: {
        apikey: key,
        authorization: `Bearer ${key}`,
        "content-type": "application/json",
        ...init.headers,
      },
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      throw new EconomicSeriesError("database_unavailable", 503);
    }
    const body = await response.text();
    return body ? JSON.parse(body) as T : undefined as T;
  } catch (error) {
    if (error instanceof EconomicSeriesError) throw error;
    throw new EconomicSeriesError("database_unavailable", 503);
  }
}

// Schema and collector share this fixed attribution; no caller-provided source is used.
export { BCB_SOURCE };
