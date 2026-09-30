export type SeriesCode = 11 | 12 | 188 | 189 | 226 | 433;
export type SeriesUnit =
  | "percent_per_day"
  | "percent_per_month"
  | "percent_per_validity_period";

export const SERIES: Readonly<Record<SeriesCode, SeriesUnit>> = {
  11: "percent_per_day",
  12: "percent_per_day",
  188: "percent_per_month",
  189: "percent_per_month",
  226: "percent_per_validity_period",
  433: "percent_per_month",
};

export const SERIES_CODES: readonly SeriesCode[] = [11, 12, 188, 189, 226, 433];
export const BCB_SOURCE = "BCB_SGS";
export const BCB_ATTRIBUTION =
  "Banco Central do Brasil, Sistema Gerenciador de Séries Temporais (SGS)";
// Licensing evidence is specific to each source dataset. Do not infer rights
// for other SGS series from the Selic catalog entry.
export const SERIES_LICENSE: Readonly<
  Partial<
    Record<SeriesCode, {
      license_id: string;
      license_url: string;
      source_dataset_url: string;
    }>
  >
> = {
  11: {
    license_id: "ODbL-1.0",
    license_url: "https://opendatacommons.org/licenses/odbl/1-0/",
    source_dataset_url:
      "https://dadosabertos.bcb.gov.br/pt_BR/dataset/11-taxa-de-juros---selic",
  },
};
export const ORIGINAL_SOURCE: Readonly<Partial<Record<SeriesCode, string>>> = {
  188: "IBGE",
  189: "FGV IBRE",
  433: "IBGE",
};
export const MAX_READ_DAYS = 366;
const MAX_COLLECT_DAYS = 366; // Strictly below the BCB ten-year cap for daily series.
const REVISION_DAYS = 40;
const MAX_RESPONSE_BYTES = 1024 * 1024;

export type EconomicObservation = {
  code: SeriesCode;
  unit: SeriesUnit;
  reference_start: string;
  reference_end: string;
  value: string;
  source: typeof BCB_SOURCE;
  fetched_at: string;
};

export type CollectionWindow = {
  from: string;
  through: string;
  nextFrom: string;
};
export type ClaimedState = {
  next_from: string;
  last_reference_start: string | null;
  last_reference_end: string | null;
  lease_token: string;
};
export type CollectorPorts = {
  fetchPage: (
    code: SeriesCode,
    window: CollectionWindow,
  ) => Promise<EconomicObservation[]>;
  upsert: (rows: EconomicObservation[]) => Promise<void>;
  complete: (
    code: SeriesCode,
    token: string,
    nextFrom: string,
    lastReferenceStart: string | null,
    lastReferenceEnd: string | null,
    count: number,
    seedRecent: boolean,
  ) => Promise<void>;
  fail: (code: SeriesCode, token: string, errorCode: string) => Promise<void>;
};

export class EconomicSeriesError extends Error {
  constructor(public readonly code: string, public readonly status = 502) {
    super(code);
    this.name = "EconomicSeriesError";
  }
}

export function isSeriesCode(value: unknown): value is SeriesCode {
  return typeof value === "number" && Number.isInteger(value) &&
    Object.hasOwn(SERIES, value);
}

export function parseIsoDate(value: unknown): string | null {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(date.getTime()) &&
      date.toISOString().slice(0, 10) === value
    ? value
    : null;
}

export function dayDiff(from: string, through: string): number {
  return Math.round(
    (Date.parse(`${through}T00:00:00Z`) -
      Date.parse(`${from}T00:00:00Z`)) / 86_400_000,
  );
}

export function addDays(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * 86_400_000)
    .toISOString().slice(0, 10);
}

export function normalizeUtcTimestamp(value: string): string {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new EconomicSeriesError("invalid_cache_timestamp", 503);
  }
  return date.toISOString();
}

export function staleDays(
  referenceStart: string | null,
  today: string,
): number | null {
  return referenceStart === null
    ? null
    : Math.max(0, dayDiff(referenceStart, today));
}

export function parseReadRequest(
  value: unknown,
  today: string = new Date().toISOString().slice(0, 10),
): {
  code: SeriesCode;
  from: string;
  through: string;
} | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  if (
    Object.keys(input).some((key) =>
      !["operation", "code", "from", "through"].includes(key)
    )
  ) return null;
  if (input.operation !== "read" || !isSeriesCode(input.code)) return null;
  const from = parseIsoDate(input.from);
  const through = parseIsoDate(input.through);
  if (
    !from || !through || dayDiff(from, through) < 0 ||
    dayDiff(from, through) >= MAX_READ_DAYS || through > today
  ) return null;
  return { code: input.code, from, through };
}

export function collectionWindow(
  nextFrom: string,
  today: string,
): CollectionWindow {
  if (!parseIsoDate(nextFrom) || !parseIsoDate(today)) {
    throw new EconomicSeriesError("invalid_checkpoint", 500);
  }
  const from = nextFrom > today ? addDays(today, -REVISION_DAYS) : nextFrom;
  const through = addDays(from, MAX_COLLECT_DAYS - 1);
  const boundedThrough = through < today ? through : today;
  return {
    from,
    through: boundedThrough,
    nextFrom: addDays(boundedThrough, 1),
  };
}

export function recentWindow(today: string): CollectionWindow {
  if (!parseIsoDate(today)) {
    throw new EconomicSeriesError("invalid_checkpoint", 500);
  }
  return {
    from: addDays(today, -(MAX_COLLECT_DAYS - 1)),
    through: today,
    nextFrom: addDays(today, 1),
  };
}

export function shouldSeedRecent(
  recentSeededAt: string | null,
  today: string,
): boolean {
  return recentSeededAt?.slice(0, 10) !== today;
}

export function parseSgsPage(
  code: SeriesCode,
  payload: unknown,
  fetchedAt: string,
  window: { from: string; through: string },
): EconomicObservation[] {
  if (!Array.isArray(payload) || !Number.isFinite(Date.parse(fetchedAt))) {
    throw new EconomicSeriesError("invalid_sgs_payload");
  }
  const parsed = new Map<string, EconomicObservation>();
  for (const item of payload) {
    if (!isRecord(item)) throw new EconomicSeriesError("invalid_sgs_payload");
    const date = parseBcbDate(item.data);
    const value = parseDecimal(item.valor);
    if (
      !date || value === null || date < window.from || date > window.through
    ) {
      throw new EconomicSeriesError("invalid_sgs_payload");
    }
    let referenceStart = date;
    let referenceEnd = date;
    if (code === 226) {
      const end = parseBcbDate(item.dataFim);
      if (!end || end < date || dayDiff(date, end) > 35) {
        throw new EconomicSeriesError("invalid_sgs_payload");
      }
      referenceEnd = end;
    } else if (SERIES[code] === "percent_per_month") {
      referenceStart = `${date.slice(0, 7)}-01`;
      referenceEnd = addDays(
        `${date.slice(0, 7)}-01`,
        new Date(
          Date.UTC(Number(date.slice(0, 4)), Number(date.slice(5, 7)), 0),
        )
          .getUTCDate() - 1,
      );
    }
    const observation: EconomicObservation = {
      code,
      unit: SERIES[code],
      reference_start: referenceStart,
      reference_end: referenceEnd,
      value,
      source: BCB_SOURCE,
      fetched_at: fetchedAt,
    };
    const old = parsed.get(referenceStart);
    if (
      old && (old.value !== observation.value ||
        old.reference_end !== observation.reference_end)
    ) {
      throw new EconomicSeriesError("invalid_sgs_payload");
    }
    parsed.set(referenceStart, observation);
  }
  return [...parsed.values()].sort((a, b) =>
    a.reference_start.localeCompare(b.reference_start)
  );
}

export function sgsUrl(
  code: SeriesCode,
  window: { from: string; through: string },
): string {
  if (
    !isSeriesCode(code) || !parseIsoDate(window.from) ||
    !parseIsoDate(window.through) || dayDiff(window.from, window.through) < 0 ||
    dayDiff(window.from, window.through) >= MAX_COLLECT_DAYS
  ) {
    throw new EconomicSeriesError("invalid_sgs_window", 400);
  }
  const url = new URL(
    `https://api.bcb.gov.br/dados/serie/bcdata.sgs.${code}/dados`,
  );
  url.searchParams.set("formato", "json");
  url.searchParams.set("dataInicial", bcbDate(window.from));
  url.searchParams.set("dataFinal", bcbDate(window.through));
  return url.toString();
}

export async function fetchSgsPage(
  code: SeriesCode,
  window: { from: string; through: string },
  fetcher: typeof fetch = fetch,
): Promise<EconomicObservation[]> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);
  try {
    const response = await fetcher(sgsUrl(code, window), {
      headers: { accept: "application/json" },
      signal: controller.signal,
    });
    // SGS returns 404 for a valid date interval without observations
    // (for example, a CDI weekend).
    if (response.status === 404) return [];
    if (!response.ok) {
      throw new EconomicSeriesError(
        response.status === 429 ? "sgs_rate_limited" : "sgs_unavailable",
      );
    }
    const length = Number(response.headers.get("content-length"));
    if (Number.isFinite(length) && length > MAX_RESPONSE_BYTES) {
      throw new EconomicSeriesError("sgs_response_too_large");
    }
    const reader = response.body?.getReader();
    if (!reader) throw new EconomicSeriesError("sgs_unavailable");
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > MAX_RESPONSE_BYTES) {
        await reader.cancel();
        throw new EconomicSeriesError("sgs_response_too_large");
      }
      chunks.push(value);
    }
    const body = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      body.set(chunk, offset);
      offset += chunk.length;
    }
    let payload: unknown;
    try {
      payload = JSON.parse(new TextDecoder().decode(body));
    } catch {
      throw new EconomicSeriesError("invalid_sgs_payload");
    }
    return parseSgsPage(code, payload, new Date().toISOString(), window);
  } catch (error) {
    if (error instanceof EconomicSeriesError) throw error;
    throw new EconomicSeriesError(
      controller.signal.aborted ? "sgs_timeout" : "sgs_unavailable",
    );
  } finally {
    clearTimeout(timeout);
  }
}

export function errorCode(error: unknown): string {
  return error instanceof EconomicSeriesError
    ? error.code
    : "collection_failed";
}

export async function collectSeries(
  code: SeriesCode,
  state: ClaimedState,
  today: string,
  ports: CollectorPorts,
  seedRecent = false,
): Promise<
  {
    code: SeriesCode;
    status: "completed" | "failed";
    count: number;
    error_code?: string;
  }
> {
  const window = seedRecent
    ? recentWindow(today)
    : collectionWindow(state.next_from, today);
  try {
    const rows = await ports.fetchPage(code, window);
    await ports.upsert(rows);
    const latest = rows.reduce<string | null>(
      (value, row) =>
        value === null || row.reference_end > value ? row.reference_end : value,
      state.last_reference_end,
    );
    const latestStart = rows.reduce<string | null>(
      (value, row) =>
        value === null || row.reference_start > value
          ? row.reference_start
          : value,
      state.last_reference_start,
    );
    await ports.complete(
      code,
      state.lease_token,
      seedRecent ? state.next_from : window.nextFrom,
      latestStart,
      latest,
      rows.length,
      seedRecent,
    );
    return { code, status: "completed", count: rows.length };
  } catch (error) {
    const failure = errorCode(error);
    await ports.fail(code, state.lease_token, failure);
    return { code, status: "failed", count: 0, error_code: failure };
  }
}

function parseBcbDate(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value);
  return match ? parseIsoDate(`${match[3]}-${match[2]}-${match[1]}`) : null;
}

function parseDecimal(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(",", ".");
  return /^-?\d{1,12}(?:\.\d{1,12})?$/.test(normalized) ? normalized : null;
}

function bcbDate(date: string): string {
  return `${date.slice(8, 10)}/${date.slice(5, 7)}/${date.slice(0, 4)}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
