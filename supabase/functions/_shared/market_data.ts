export type Provider = "brapi" | "twelveData" | "coinGecko";
export type DbProvider = "brapi" | "twelve_data" | "coin_gecko";
export type QuotePurpose = "portfolio" | "preview" | "manualRefresh";

export type SearchRequest = {
  operation: "search";
  query: string;
  asset_class: string;
  currency: string;
  limit?: number;
};

export type QuoteRequest = {
  operation?: "quote";
  asset_id?: string | null;
  provider: Provider;
  instrument_id?: string | null;
  symbol: string;
  provider_symbol?: string | null;
  asset_class: string;
  currency: string;
  exchange?: string | null;
  purpose?: QuotePurpose;
};

export type HeartbeatRequest = {
  operation: "heartbeat";
  assets: Array<{
    provider: Provider;
    provider_symbol: string;
    currency: string;
    exchange?: string | null;
  }>;
};

export type SearchCandidate = {
  asset_id?: string;
  symbol: string;
  name: string;
  asset_class: string;
  currency: string;
  exchange: string | null;
  mic_code?: string | null;
  country?: string | null;
  isin?: string | null;
  provider: Provider;
  provider_symbol: string;
  relevance_score?: number;
  source_rank?: number;
};

export type NormalizedQuote = {
  price: string;
  currency: string;
  timestamp: number;
  provider: string;
  asset_id?: string;
  fetched_at?: string;
  stale?: boolean;
  refresh_failed?: boolean;
  error_code?: string | null;
  source?: "database" | "provider";
};

export type RefreshTarget = {
  asset_id: string;
  symbol: string;
  asset_class: string;
  currency: string;
  exchange: string;
  provider: DbProvider;
  provider_symbol: string;
  lease_token: string;
};

type ProviderSettings = {
  provider: DbProvider;
  catalog_enabled: boolean;
  persistence_allowed: boolean;
  redistribution_allowed: boolean;
  catalog_cursor: Record<string, unknown>;
};

type LatestQuoteRow = {
  asset_id: number | string;
  price: number | string;
  currency: string;
  quoted_at: string;
  fetched_at: string;
  provider: DbProvider;
  is_stale: boolean;
  error_code: string | null;
};

export class MarketDataError extends Error {
  constructor(public readonly code: string, public readonly status = 502) {
    super(code);
    this.name = "MarketDataError";
  }
}

const SUPPORTED_ASSET_CLASSES = new Set([
  "stock",
  "etf",
  "fund",
  "reit",
  "fii",
  "bond",
  "fixed_income",
  "crypto",
  "commodity",
  "cash_equivalent",
  "other",
]);
const settingsCache = new Map<DbProvider, ProviderSettings>();
export const TWELVE_DATA_CATALOG_PAGE_SIZE = 500;
export const TWELVE_DATA_CATALOG_PAGES_PER_RUN = 8;
const PROVIDER_FETCH_TIMEOUT_MS = 20_000;
const TWELVE_DATA_CATALOG_MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
const STALE_SYNC_RUN_AGE_MS = 10 * 60 * 1000;

export type TwelveDataCatalogCheckpoint = {
  nextPage: number;
  imported: number;
  discovered: number;
  cycleRunId: string;
};

export function catalogReadEnabled(): boolean {
  return Deno.env.get("MARKET_CATALOG_READ_ENABLED")?.toLowerCase() === "true";
}

export function scheduledQuotesEnabled(): boolean {
  return Deno.env.get("MARKET_SCHEDULED_QUOTES_ENABLED")?.toLowerCase() ===
    "true";
}

export function databaseConfigured(): boolean {
  return Boolean(
    Deno.env.get("SUPABASE_URL") && Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  );
}

export function toDbProvider(provider: Provider): DbProvider {
  if (provider === "twelveData") return "twelve_data";
  if (provider === "coinGecko") return "coin_gecko";
  return "brapi";
}

export function fromDbProvider(provider: DbProvider): Provider {
  if (provider === "twelve_data") return "twelveData";
  if (provider === "coin_gecko") return "coinGecko";
  return "brapi";
}

export function normalizeProviderSymbol(
  provider: Provider,
  symbol: string,
): string {
  const value = symbol.trim();
  return provider === "coinGecko" ? value.toLowerCase() : value.toUpperCase();
}

export function canonicalAssetKey(candidate: SearchCandidate): string {
  const isin = candidate.isin?.trim().toUpperCase();
  if (isin) return `isin:${isin}`;
  if (candidate.provider === "coinGecko") {
    return `crypto:coingecko:${
      normalizeProviderSymbol(candidate.provider, candidate.provider_symbol)
    }:${candidate.currency.toUpperCase()}`;
  }
  const exchange = (candidate.exchange ?? "").trim().toUpperCase();
  return [
    "provider",
    toDbProvider(candidate.provider),
    exchange,
    normalizeProviderSymbol(candidate.provider, candidate.provider_symbol),
    candidate.currency.toUpperCase(),
    candidate.asset_class,
  ].join(":");
}

export function candidateScore(
  candidate: SearchCandidate,
  input: SearchRequest,
): number {
  const query = input.query.trim().toUpperCase();
  const symbol = candidate.symbol.toUpperCase();
  const name = candidate.name.toUpperCase();
  let score = candidate.currency === input.currency ? 1000 : 0;
  if (symbol === query) score += 10000;
  else if (symbol.startsWith(query)) score += 5000;
  if (name === query) score += 3000;
  else if (name.startsWith(query)) score += 2000;
  score += Math.min(999, Math.max(0, candidate.relevance_score ?? 0));
  return score;
}

export function deduplicateCandidates(
  values: SearchCandidate[],
): SearchCandidate[] {
  const seen = new Set<string>();
  return values.filter((value) => {
    const key = [
      toDbProvider(value.provider),
      normalizeProviderSymbol(value.provider, value.provider_symbol),
      (value.exchange ?? "").toUpperCase(),
    ].join("|");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function providersFor(assetClass: string): Provider[] {
  if (assetClass === "crypto") return ["coinGecko"];
  if (assetClass === "fii") return ["brapi"];
  if (["stock", "etf", "fund", "reit"].includes(assetClass)) {
    return ["brapi", "twelveData"];
  }
  return ["twelveData"];
}

export async function searchCatalog(
  input: SearchRequest,
): Promise<SearchCandidate[]> {
  if (!databaseConfigured() || !catalogReadEnabled()) return [];
  const rows = await databaseRequest<Array<Record<string, unknown>>>(
    "/rest/v1/rpc/search_market_assets",
    {
      method: "POST",
      body: JSON.stringify({
        p_query: input.query.trim(),
        p_asset_class: input.asset_class,
        p_currency: input.currency,
        p_limit: Math.min(Math.max(input.limit ?? 10, 1), 10),
      }),
    },
  );
  return rows.map(candidateFromCatalogRow);
}

export async function searchProviders(
  input: SearchRequest,
): Promise<{ results: SearchCandidate[]; failed: Provider[] }> {
  const limit = Math.min(Math.max(input.limit ?? 10, 1), 10);
  const providers = providersFor(input.asset_class);
  const settled = await Promise.allSettled(
    providers.map((provider) => searchProvider(provider, input, limit)),
  );
  const results: SearchCandidate[] = [];
  const failed: Provider[] = [];
  for (let index = 0; index < settled.length; index += 1) {
    const result = settled[index];
    if (result.status === "fulfilled") results.push(...result.value);
    else failed.push(providers[index]);
  }
  return { results: deduplicateCandidates(results), failed };
}

export async function persistCandidates(
  candidates: SearchCandidate[],
  options: { runId?: string; active?: boolean } = {},
): Promise<SearchCandidate[]> {
  if (!databaseConfigured() || candidates.length === 0) return candidates;
  const persisted: SearchCandidate[] = [];
  for (const provider of ["brapi", "twelveData", "coinGecko"] as const) {
    const settings = await providerSettings(toDbProvider(provider));
    if (
      !settings.catalog_enabled || !settings.persistence_allowed ||
      !settings.redistribution_allowed
    ) {
      persisted.push(
        ...candidates.filter((item) => item.provider === provider),
      );
      continue;
    }
    const values = candidates.filter((item) => item.provider === provider);
    for (let offset = 0; offset < values.length; offset += 500) {
      const batch = values.slice(offset, offset + 500);
      const assetsByKey = new Map<string, Record<string, unknown>>();
      for (const candidate of batch) {
        const canonicalKey = canonicalAssetKey(candidate);
        if (assetsByKey.has(canonicalKey)) continue;
        assetsByKey.set(canonicalKey, {
          canonical_key: canonicalKey,
          symbol: candidate.symbol.trim().toUpperCase(),
          name: candidate.name.trim(),
          asset_class: candidate.asset_class,
          currency: candidate.currency.toUpperCase(),
          exchange: (candidate.exchange ?? "").trim().toUpperCase(),
          mic_code: candidate.mic_code?.trim().toUpperCase() || null,
          country: candidate.country?.trim() || null,
          isin: normalizeIsin(candidate.isin),
          is_active: options.active ?? true,
          relevance_score: candidate.relevance_score ?? 0,
          last_seen_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        });
      }
      const assets = [...assetsByKey.values()];
      const rows = await databaseRequest<
        Array<{ id: number | string; canonical_key: string }>
      >(
        "/rest/v1/market_assets?on_conflict=canonical_key&select=id,canonical_key",
        {
          method: "POST",
          headers: {
            Prefer: "resolution=merge-duplicates,return=representation",
          },
          body: JSON.stringify(assets),
        },
      );
      const ids = new Map(
        rows.map((row) => [row.canonical_key, String(row.id)]),
      );
      const sourcesByKey = new Map<string, Record<string, unknown>>();
      for (const candidate of batch) {
        const assetId = ids.get(canonicalAssetKey(candidate));
        if (assetId == null) continue;
        const providerSymbol = normalizeProviderSymbol(
          candidate.provider,
          candidate.provider_symbol,
        );
        const exchange = (candidate.exchange ?? "").trim().toUpperCase();
        const currency = candidate.currency.toUpperCase();
        const sourceKey = [
          toDbProvider(candidate.provider),
          providerSymbol,
          exchange,
          currency,
        ].join("|");
        if (sourcesByKey.has(sourceKey)) continue;
        const isin = normalizeIsin(candidate.isin);
        sourcesByKey.set(sourceKey, {
          asset_id: assetId,
          provider: toDbProvider(candidate.provider),
          provider_symbol: providerSymbol,
          external_identifiers: {
            ...(isin ? { isin } : {}),
            ...(candidate.mic_code
              ? { mic_code: candidate.mic_code.trim().toUpperCase() }
              : {}),
          },
          exchange,
          currency,
          source_rank: candidate.source_rank ?? null,
          is_active: options.active ?? true,
          missing_sync_count: 0,
          last_seen_run_id: options.runId ?? null,
          last_seen_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        });
      }
      const sources = [...sourcesByKey.values()];
      if (sources.length > 0) {
        await databaseRequest(
          "/rest/v1/market_asset_sources?on_conflict=provider,provider_symbol,exchange,currency",
          {
            method: "POST",
            headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
            body: JSON.stringify(sources),
          },
        );
      }
      persisted.push(...batch.map((candidate) => ({
        ...candidate,
        asset_id: ids.get(canonicalAssetKey(candidate)) ?? candidate.asset_id,
      })));
    }
  }
  return persisted;
}

export async function renewTargets(
  assets: HeartbeatRequest["assets"],
  activity: "portfolio" | "preview" | "manual_refresh",
): Promise<number> {
  if (!databaseConfigured() || assets.length === 0) return 0;
  return await databaseRequest<number>(
    "/rest/v1/rpc/renew_market_asset_targets",
    {
      method: "POST",
      body: JSON.stringify({
        p_assets: assets.slice(0, 200),
        p_activity: activity,
      }),
    },
  );
}

export async function quoteWithCache(
  input: QuoteRequest,
): Promise<NormalizedQuote> {
  const purpose = input.purpose ?? "manualRefresh";
  const useDatabase = databaseConfigured() && catalogReadEnabled();
  const assetId = useDatabase
    ? input.asset_id ?? await resolveAssetId(input)
    : null;
  if (assetId) {
    await renewTargets([{
      provider: input.provider,
      provider_symbol: normalizeProviderSymbol(
        input.provider,
        input.provider_symbol ?? input.symbol,
      ),
      currency: input.currency,
      exchange: input.exchange,
    }], activityForPurpose(purpose));
  }
  const previous = assetId ? await latestQuote(assetId) : null;
  const maximumAge = purpose === "portfolio"
    ? 24 * 60 * 60 * 1000
    : purpose === "preview"
    ? 15 * 60 * 1000
    : 5 * 60 * 1000;
  if (
    previous && !previous.is_stale &&
    Date.now() - Date.parse(previous.fetched_at) <= maximumAge
  ) {
    return quoteFromRow(previous, false);
  }
  const provider = toDbProvider(input.provider);
  if (useDatabase && !(await reserveCredits(provider, "interactive", 1))) {
    if (previous) return quoteFromRow(previous, true, "rate_limited");
    throw new MarketDataError("rate_limited", 429);
  }
  try {
    const quote = await fetchProviderQuote(input);
    if (assetId) await saveQuote(assetId, quote, false);
    return {
      ...quote,
      asset_id: assetId ?? undefined,
      stale: false,
      refresh_failed: false,
      source: "provider",
    };
  } catch (error) {
    const code = providerErrorCode(error);
    if (assetId) await markLatestQuoteStale(assetId, code);
    if (previous) return quoteFromRow(previous, true, code);
    if (error instanceof MarketDataError) throw error;
    throw new MarketDataError(code);
  }
}

export async function createSyncRun(
  provider: DbProvider | "system",
  operation: "catalog" | "ranking" | "quotes" | "cleanup" | "on_demand",
): Promise<string> {
  const rows = await databaseRequest<Array<{ id: number | string }>>(
    "/rest/v1/market_sync_runs?select=id",
    {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({ provider, operation, status: "running" }),
    },
  );
  return String(rows[0].id);
}

export async function finishSyncRun(
  runId: string,
  status: "completed" | "partial" | "failed" | "disabled",
  counters: Record<string, number>,
  errorCode?: string,
): Promise<void> {
  await databaseRequest(
    `/rest/v1/market_sync_runs?id=eq.${encodeURIComponent(runId)}`,
    {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        status,
        counters,
        error_code: errorCode ?? null,
        completed_at: new Date().toISOString(),
      }),
    },
  );
}

async function finalizeStaleSyncRuns(
  provider: DbProvider,
  operation: "catalog" | "ranking" | "quotes" | "cleanup" | "on_demand",
): Promise<void> {
  const cutoff = new Date(Date.now() - STALE_SYNC_RUN_AGE_MS).toISOString();
  await databaseRequest(
    `/rest/v1/market_sync_runs?provider=eq.${provider}` +
      `&operation=eq.${operation}&status=eq.running` +
      `&started_at=lt.${encodeURIComponent(cutoff)}`,
    {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        status: "failed",
        counters: { orphaned: 1 },
        error_code: "edge_worker_timeout",
        completed_at: new Date().toISOString(),
      }),
    },
  );
}

export async function completeCatalogRun(
  runId: string,
  provider: DbProvider,
  complete: boolean,
): Promise<void> {
  await databaseRequest("/rest/v1/rpc/complete_market_catalog_run", {
    method: "POST",
    body: JSON.stringify({
      p_run_id: Number(runId),
      p_provider: provider,
      p_complete: complete,
    }),
  });
}

export async function syncTwelveDataCatalog(): Promise<Record<string, number>> {
  const provider: DbProvider = "twelve_data";
  const settings = await providerSettings(provider, true);
  await finalizeStaleSyncRuns(provider, "catalog");
  const runId = await createSyncRun(provider, "catalog");
  const disabledReason = catalogDisabledReason(settings);
  if (disabledReason) {
    await finishSyncRun(
      runId,
      "disabled",
      { imported: 0 },
      disabledReason,
    );
    return { imported: 0, disabled: 1 };
  }
  const checkpoint = restoreTwelveDataCheckpoint(
    settings.catalog_cursor,
    TWELVE_DATA_CATALOG_PAGE_SIZE,
    runId,
  );
  let currentPage = checkpoint.nextPage;
  let discovered = checkpoint.discovered;
  let imported = checkpoint.imported;
  let pages = 0;
  let completed = false;
  let rateLimited = false;
  try {
    const token = Deno.env.get("TWELVE_DATA_API_KEY");
    if (!token) throw new MarketDataError("twelve_data_not_configured");
    for (
      let pageIndex = 0;
      pageIndex < TWELVE_DATA_CATALOG_PAGES_PER_RUN;
      pageIndex += 1
    ) {
      if (!(await reserveCredits(provider, "scheduled", 1))) {
        rateLimited = true;
        break;
      }
      const requestedPage = currentPage;
      const url = twelveDataCatalogUrl(token, requestedPage);
      let body: Record<string, unknown>;
      try {
        body = await withProviderTimeout(
          async (signal) =>
            await checkedJson(
              await fetch(url, { signal }),
              TWELVE_DATA_CATALOG_MAX_RESPONSE_BYTES,
            ),
        );
      } catch (error) {
        if (providerErrorCode(error) === "rate_limited") {
          rateLimited = true;
          break;
        }
        throw error;
      }
      const rows = Array.isArray(body.data) ? body.data : [];
      const candidates = rows
        .filter(isRecord)
        .map((row) => twelveCatalogCandidate(row))
        .filter((candidate): candidate is SearchCandidate => candidate != null);
      await persistCandidates(candidates, {
        runId: checkpoint.cycleRunId,
        active: true,
      });
      pages += 1;
      discovered += rows.length;
      imported += candidates.length;
      currentPage = requestedPage + 1;
      completed = isTwelveDataCatalogPageComplete(rows.length);
      await saveCatalogCheckpoint(
        provider,
        runId,
        {
          stage: "twelve_catalog",
          cursor_version: 2,
          page_size: TWELVE_DATA_CATALOG_PAGE_SIZE,
          next_page: currentPage,
          discovered,
          imported,
          cycle_run_id: checkpoint.cycleRunId,
          complete: completed,
        },
        completed,
      );
      if (completed) break;
    }
    const counters = {
      pages,
      discovered,
      imported,
      next_page: completed ? 0 : currentPage,
    };
    if (completed) {
      await completeCatalogRun(checkpoint.cycleRunId, provider, true);
      await finishSyncRun(runId, "completed", counters);
      return { ...counters, complete: 1 };
    }
    await finishSyncRun(
      runId,
      "partial",
      counters,
      rateLimited ? "rate_limited" : undefined,
    );
    return {
      ...counters,
      ...(rateLimited ? { rate_limited: 1 } : { pending: 1 }),
    };
  } catch (error) {
    await finishSyncRun(
      runId,
      "failed",
      { pages, discovered, imported, next_page: currentPage },
      providerErrorCode(error),
    );
    throw error;
  }
}

export async function syncCoinGeckoCatalog(): Promise<Record<string, number>> {
  const provider: DbProvider = "coin_gecko";
  const settings = await providerSettings(provider, true);
  const runId = await createSyncRun(provider, "catalog");
  const disabledReason = catalogDisabledReason(settings);
  if (disabledReason) {
    await finishSyncRun(
      runId,
      "disabled",
      { imported: 0 },
      disabledReason,
    );
    return { imported: 0, disabled: 1 };
  }
  try {
    const candidates: SearchCandidate[] = [];
    for (let page = 1; page <= 2; page += 1) {
      if (!(await reserveCredits(provider, "scheduled", 1))) break;
      const url = new URL("https://api.coingecko.com/api/v3/coins/markets");
      url.searchParams.set("vs_currency", "usd");
      url.searchParams.set("order", "market_cap_desc");
      url.searchParams.set("per_page", "250");
      url.searchParams.set("page", String(page));
      url.searchParams.set("sparkline", "false");
      const token = Deno.env.get("COINGECKO_API_KEY");
      const body = await checkedJsonArray(
        await fetch(url, {
          headers: token ? { "x-cg-demo-api-key": token } : {},
        }),
      );
      for (const row of body.filter(isRecord)) {
        const id = String(row.id ?? "").trim();
        const symbol = String(row.symbol ?? "").trim().toUpperCase();
        const name = String(row.name ?? "").trim();
        const rank = Number(row.market_cap_rank ?? candidates.length + 1);
        if (!id || !symbol || !name) continue;
        candidates.push({
          symbol,
          name,
          asset_class: "crypto",
          currency: "USD",
          exchange: null,
          provider: "coinGecko",
          provider_symbol: id,
          source_rank: rank,
          relevance_score: Math.max(0, 1000 - rank),
        });
      }
    }
    const selected = candidates.sort((a, b) =>
      (a.source_rank ?? 999999) - (b.source_rank ?? 999999)
    ).slice(0, 500);
    await persistCandidates(selected, { runId, active: true });
    await completeCatalogRun(runId, provider, selected.length === 500);
    await finishSyncRun(
      runId,
      selected.length === 500 ? "completed" : "partial",
      { imported: selected.length },
    );
    return { imported: selected.length };
  } catch (error) {
    await finishSyncRun(
      runId,
      "failed",
      { imported: 0 },
      providerErrorCode(error),
    );
    throw error;
  }
}

export async function syncBrapiCatalog(): Promise<Record<string, number>> {
  const provider: DbProvider = "brapi";
  const settings = await providerSettings(provider, true);
  const runId = await createSyncRun(provider, "ranking");
  const disabledReason = catalogDisabledReason(settings);
  if (disabledReason) {
    await finishSyncRun(
      runId,
      "disabled",
      { imported: 0 },
      disabledReason,
    );
    return { imported: 0, disabled: 1 };
  }
  try {
    if (!(await reserveCredits(provider, "scheduled", 1))) {
      await finishSyncRun(runId, "partial", { imported: 0 }, "rate_limited");
      return { imported: 0, rate_limited: 1 };
    }
    const listUrl = new URL("https://brapi.dev/api/v2/tickers");
    listUrl.searchParams.set("limit", "1000");
    const token = Deno.env.get("BRAPI_API_TOKEN");
    const body = await checkedJson(
      await fetch(listUrl, {
        headers: token ? { authorization: `Bearer ${token}` } : {},
      }),
    );
    const rows = (Array.isArray(body.results)
      ? body.results
      : Array.isArray(body.stocks)
      ? body.stocks
      : [])
      .filter(isRecord);
    const candidates = rows.map(brapiCatalogCandidate).filter((
      value,
    ): value is SearchCandidate =>
      value != null
    );
    const checkpoint = restoreBrapiCheckpoint(
      settings.catalog_cursor,
      candidates.length,
    );
    const metrics = new Map<string, number>(Object.entries(checkpoint.metrics));
    let complete = true;
    for (
      let offset = checkpoint.offset;
      offset < candidates.length;
      offset += 20
    ) {
      if (!(await reserveCredits(provider, "scheduled", 1))) {
        complete = false;
        break;
      }
      const batch = candidates.slice(offset, offset + 20);
      try {
        const quoteUrl = new URL("https://brapi.dev/api/v2/stocks/quote");
        quoteUrl.searchParams.set(
          "symbols",
          batch.map((item) => item.provider_symbol).join(","),
        );
        const quoteBody = await checkedJson(
          await fetch(quoteUrl, {
            headers: token ? { authorization: `Bearer ${token}` } : {},
          }),
        );
        const quoteRows = Array.isArray(quoteBody.results)
          ? quoteBody.results.filter(isRecord)
          : [];
        for (const result of quoteRows) {
          const data = isRecord(result.data) ? result.data : result;
          const symbol = String(
            result.symbol ?? result.requestedSymbol ?? data.symbol ?? "",
          ).toUpperCase();
          const price = Number(data.regularMarketPrice ?? 0);
          const volume = Number(data.regularMarketVolume ?? 0);
          const marketCap = Number(data.marketCap ?? 0);
          const turnover = Math.max(0, price * volume);
          metrics.set(
            symbol,
            Math.log1p(Math.max(0, marketCap)) + 0.35 * Math.log1p(turnover),
          );
        }
        await saveCatalogCheckpoint(provider, runId, {
          stage: "brapi_ranking",
          asset_count: candidates.length,
          offset: Math.min(offset + batch.length, candidates.length),
          metrics: Object.fromEntries(metrics),
        });
      } catch {
        complete = false;
        break;
      }
    }
    const ranked = candidates
      .map((candidate) => ({
        ...candidate,
        relevance_score: metrics.get(candidate.provider_symbol) ?? 0,
      }))
      .sort((a, b) => (b.relevance_score ?? 0) - (a.relevance_score ?? 0));
    const selected = new Map<string, SearchCandidate>();
    for (const candidate of ranked.slice(0, 500)) {
      selected.set(canonicalAssetKey(candidate), candidate);
    }
    for (
      const assetClass of new Set(
        ranked.map((item) => item.asset_class).filter((value) =>
          value !== "stock"
        ),
      )
    ) {
      for (
        const candidate of ranked.filter((item) =>
          item.asset_class === assetClass
        ).slice(0, 50)
      ) {
        selected.set(canonicalAssetKey(candidate), candidate);
      }
    }
    const values = [...selected.values()].map((candidate, index) => ({
      ...candidate,
      source_rank: index + 1,
    }));
    await persistCandidates(values, { runId, active: true });
    await completeCatalogRun(runId, provider, complete);
    if (complete) {
      await saveCatalogCheckpoint(provider, runId, {
        complete: true,
        asset_count: candidates.length,
        offset: candidates.length,
      }, true);
    }
    await finishSyncRun(runId, complete ? "completed" : "partial", {
      discovered: candidates.length,
      ranked: metrics.size,
      imported: values.length,
    });
    return {
      discovered: candidates.length,
      ranked: metrics.size,
      imported: values.length,
    };
  } catch (error) {
    await finishSyncRun(
      runId,
      "failed",
      { imported: 0 },
      providerErrorCode(error),
    );
    throw error;
  }
}

export async function claimRefreshTargets(
  limit = 100,
): Promise<RefreshTarget[]> {
  return await databaseRequest<RefreshTarget[]>(
    "/rest/v1/rpc/claim_market_refresh_targets",
    {
      method: "POST",
      body: JSON.stringify({ p_limit: limit, p_lease_seconds: 300 }),
    },
  );
}

export async function refreshTrackedTarget(
  target: RefreshTarget,
): Promise<NormalizedQuote> {
  const provider = fromDbProvider(target.provider);
  const input: QuoteRequest = {
    operation: "quote",
    asset_id: target.asset_id,
    provider,
    symbol: target.symbol,
    provider_symbol: target.provider_symbol,
    asset_class: target.asset_class,
    currency: target.currency,
    exchange: target.exchange || null,
    purpose: "portfolio",
  };
  const previous = await latestQuote(target.asset_id);
  const maximumAge = provider === "coinGecko"
    ? 11 * 60 * 60 * 1000
    : 20 * 60 * 60 * 1000;
  if (
    previous && !previous.is_stale &&
    Date.now() - Date.parse(previous.fetched_at) <= maximumAge
  ) {
    return quoteFromRow(previous, false);
  }
  if (!(await reserveCredits(target.provider, "scheduled", 1))) {
    if (previous) return quoteFromRow(previous, true, "rate_limited");
    throw new MarketDataError("rate_limited", 429);
  }
  try {
    const quote = await fetchProviderQuote(input);
    await saveQuote(
      target.asset_id,
      quote,
      shouldStoreDailyQuote(target.provider, target.exchange, new Date()),
    );
    return { ...quote, asset_id: target.asset_id, source: "provider" };
  } catch (error) {
    const code = providerErrorCode(error);
    await markLatestQuoteStale(target.asset_id, code);
    if (previous) return quoteFromRow(previous, true, code);
    throw error;
  }
}

export async function completeRefreshTarget(
  target: RefreshTarget,
  success: boolean,
  errorCode?: string,
): Promise<void> {
  await databaseRequest("/rest/v1/rpc/complete_market_refresh", {
    method: "POST",
    body: JSON.stringify({
      p_asset_id: Number(target.asset_id),
      p_lease_token: target.lease_token,
      p_success: success,
      p_next_refresh_at: nextMarketRefreshAt(
        target.provider,
        target.exchange,
        success,
      ),
      p_error_code: errorCode ?? null,
    }),
  });
}

export async function pruneMarketData(): Promise<Record<string, number>> {
  const rows = await databaseRequest<
    Array<{ quotes_deleted: number; targets_deleted: number }>
  >(
    "/rest/v1/rpc/prune_market_quote_history",
    { method: "POST", body: "{}" },
  );
  return rows[0] ?? { quotes_deleted: 0, targets_deleted: 0 };
}

export async function fetchProviderQuote(
  input: QuoteRequest,
): Promise<NormalizedQuote> {
  if (input.provider === "brapi") return await brapiQuote(input);
  if (input.provider === "coinGecko") return await coinGeckoQuote(input);
  return await twelveDataQuote(input);
}

export function providerErrorCode(error: unknown): string {
  if (error instanceof MarketDataError) return error.code;
  if (error instanceof TypeError) return "network";
  return "provider_unavailable";
}

async function searchProvider(
  provider: Provider,
  input: SearchRequest,
  limit: number,
): Promise<SearchCandidate[]> {
  if (provider === "brapi") return await searchBrapi(input, limit);
  if (provider === "coinGecko") return await searchCoinGecko(input, limit);
  return await searchTwelveData(input, limit);
}

async function searchBrapi(
  input: SearchRequest,
  limit: number,
): Promise<SearchCandidate[]> {
  const url = new URL("https://brapi.dev/api/v2/tickers");
  url.searchParams.set("search", input.query.trim());
  url.searchParams.set("limit", String(limit));
  const token = Deno.env.get("BRAPI_API_TOKEN");
  const body = await checkedJson(
    await fetch(url, {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    }),
  );
  const rows = Array.isArray(body.results) ? body.results : [];
  return rows.filter(isRecord).map(brapiCatalogCandidate)
    .filter((value): value is SearchCandidate => value != null);
}

async function searchTwelveData(
  input: SearchRequest,
  limit: number,
): Promise<SearchCandidate[]> {
  const token = Deno.env.get("TWELVE_DATA_API_KEY");
  if (!token) throw new MarketDataError("twelve_data_not_configured");
  const url = new URL("https://api.twelvedata.com/symbol_search");
  url.searchParams.set("symbol", input.query.trim());
  url.searchParams.set("outputsize", String(limit));
  url.searchParams.set("show_plan", "true");
  url.searchParams.set("apikey", token);
  const body = await checkedJson(await fetch(url));
  const rows = Array.isArray(body.data) ? body.data : [];
  return rows.filter(isRecord).map((row) => ({
    symbol: String(row.symbol ?? "").toUpperCase(),
    name: String(row.instrument_name ?? row.symbol ?? "").trim(),
    asset_class: twelveDataClass(
      String(row.instrument_type ?? ""),
      input.asset_class,
    ),
    currency: String(row.currency ?? input.currency).toUpperCase(),
    exchange: String(row.exchange ?? row.mic_code ?? "").toUpperCase() || null,
    mic_code: String(row.mic_code ?? "").toUpperCase() || null,
    country: String(row.country ?? "") || null,
    provider: "twelveData" as const,
    provider_symbol: String(row.symbol ?? "").toUpperCase(),
  })).filter(validCandidate);
}

async function searchCoinGecko(
  input: SearchRequest,
  limit: number,
): Promise<SearchCandidate[]> {
  const url = new URL("https://api.coingecko.com/api/v3/search");
  url.searchParams.set("query", input.query.trim());
  const token = Deno.env.get("COINGECKO_API_KEY");
  const body = await checkedJson(
    await fetch(url, {
      headers: token ? { "x-cg-demo-api-key": token } : {},
    }),
  );
  const rows = Array.isArray(body.coins) ? body.coins : [];
  return rows.filter(isRecord).slice(0, limit).map((row) => ({
    symbol: String(row.symbol ?? "").toUpperCase(),
    name: String(row.name ?? row.symbol ?? "").trim(),
    asset_class: "crypto",
    currency: input.currency,
    exchange: null,
    provider: "coinGecko" as const,
    provider_symbol: String(row.id ?? "").toLowerCase(),
    source_rank: Number(row.market_cap_rank ?? 0) || undefined,
  })).filter(validCandidate);
}

async function brapiQuote(input: QuoteRequest): Promise<NormalizedQuote> {
  const symbol = normalizeProviderSymbol(
    "brapi",
    input.provider_symbol ?? input.symbol,
  );
  const url = new URL("https://brapi.dev/api/v2/stocks/quote");
  url.searchParams.set("symbols", symbol);
  const token = Deno.env.get("BRAPI_API_TOKEN");
  const body = await checkedJson(
    await fetch(url, {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    }),
  );
  const result = Array.isArray(body.results) && isRecord(body.results[0])
    ? body.results[0]
    : null;
  const data = result && isRecord(result.data) ? result.data : result;
  if (!data) throw new MarketDataError("invalid_provider_response");
  const price = positiveDecimal(data.regularMarketPrice);
  const currency = String(data.currency ?? input.currency).toUpperCase();
  const quotedAt = Date.parse(String(data.regularMarketTime ?? ""));
  return {
    price,
    currency,
    timestamp: Number.isFinite(quotedAt) ? quotedAt * 1000 : Date.now() * 1000,
    fetched_at: new Date().toISOString(),
    provider: "brapi",
  };
}

async function twelveDataQuote(input: QuoteRequest): Promise<NormalizedQuote> {
  const token = Deno.env.get("TWELVE_DATA_API_KEY");
  if (!token) throw new MarketDataError("twelve_data_not_configured");
  const url = new URL("https://api.twelvedata.com/price");
  url.searchParams.set(
    "symbol",
    normalizeProviderSymbol(
      "twelveData",
      input.provider_symbol ?? input.symbol,
    ),
  );
  if (input.exchange) url.searchParams.set("exchange", input.exchange);
  url.searchParams.set("apikey", token);
  const body = await checkedJson(await fetch(url));
  return {
    price: positiveDecimal(body.price),
    currency: input.currency,
    timestamp: Date.now() * 1000,
    fetched_at: new Date().toISOString(),
    provider: "twelve_data",
  };
}

async function coinGeckoQuote(input: QuoteRequest): Promise<NormalizedQuote> {
  const id = normalizeProviderSymbol(
    "coinGecko",
    input.provider_symbol ?? input.symbol,
  );
  const currency = input.currency.toLowerCase();
  const url = new URL("https://api.coingecko.com/api/v3/simple/price");
  url.searchParams.set("ids", id);
  url.searchParams.set("vs_currencies", currency);
  url.searchParams.set("include_last_updated_at", "true");
  url.searchParams.set("precision", "full");
  const token = Deno.env.get("COINGECKO_API_KEY");
  const body = await checkedJson(
    await fetch(url, {
      headers: token ? { "x-cg-demo-api-key": token } : {},
    }),
  );
  const row = isRecord(body[id]) ? body[id] : null;
  if (!row) throw new MarketDataError("invalid_provider_response");
  const updated = Number(row.last_updated_at ?? 0);
  return {
    price: positiveDecimal(row[currency]),
    currency: input.currency,
    timestamp: updated > 0 ? updated * 1_000_000 : Date.now() * 1000,
    fetched_at: new Date().toISOString(),
    provider: "coingecko",
  };
}

async function resolveAssetId(input: QuoteRequest): Promise<string | null> {
  if (!databaseConfigured()) return null;
  const provider = toDbProvider(input.provider);
  const symbol = normalizeProviderSymbol(
    input.provider,
    input.provider_symbol ?? input.symbol,
  );
  const exchange = (input.exchange ?? "").trim().toUpperCase();
  const filters = [
    `provider=eq.${encodeURIComponent(provider)}`,
    `provider_symbol=eq.${encodeURIComponent(symbol)}`,
    `currency=eq.${encodeURIComponent(input.currency)}`,
    exchange ? `exchange=eq.${encodeURIComponent(exchange)}` : "",
    "select=asset_id",
    "limit=1",
  ].filter(Boolean).join("&");
  const rows = await databaseRequest<Array<{ asset_id: number | string }>>(
    `/rest/v1/market_asset_sources?${filters}`,
  );
  if (rows.length > 0) return String(rows[0].asset_id);
  const [persisted] = await persistCandidates([{
    symbol: input.symbol.toUpperCase(),
    name: input.symbol.toUpperCase(),
    asset_class: input.asset_class,
    currency: input.currency,
    exchange: input.exchange ?? null,
    provider: input.provider,
    provider_symbol: symbol,
  }]);
  return persisted?.asset_id ?? null;
}

async function latestQuote(assetId: string): Promise<LatestQuoteRow | null> {
  if (!databaseConfigured()) return null;
  const rows = await databaseRequest<LatestQuoteRow[]>(
    `/rest/v1/market_asset_quotes_latest?asset_id=eq.${
      encodeURIComponent(assetId)
    }&select=*&limit=1`,
  );
  return rows[0] ?? null;
}

async function saveQuote(
  assetId: string,
  quote: NormalizedQuote,
  daily: boolean,
): Promise<void> {
  const provider = quote.provider === "twelve_data"
    ? "twelve_data"
    : quote.provider === "coingecko"
    ? "coin_gecko"
    : "brapi";
  const quotedAt = new Date(Math.floor(quote.timestamp / 1000)).toISOString();
  const fetchedAt = quote.fetched_at ?? new Date().toISOString();
  await databaseRequest(
    "/rest/v1/market_asset_quotes_latest?on_conflict=asset_id",
    {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        asset_id: Number(assetId),
        price: quote.price,
        currency: quote.currency,
        quoted_at: quotedAt,
        fetched_at: fetchedAt,
        provider,
        is_stale: false,
        error_code: null,
      }),
    },
  );
  if (daily) {
    await databaseRequest(
      "/rest/v1/market_asset_quotes_daily?on_conflict=asset_id,quote_date",
      {
        method: "POST",
        headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify({
          asset_id: Number(assetId),
          quote_date: quotedAt.slice(0, 10),
          close_price: quote.price,
          currency: quote.currency,
          quoted_at: quotedAt,
          fetched_at: fetchedAt,
          provider,
        }),
      },
    );
  }
}

async function markLatestQuoteStale(
  assetId: string,
  errorCode: string,
): Promise<void> {
  if (!databaseConfigured()) return;
  await databaseRequest(
    `/rest/v1/market_asset_quotes_latest?asset_id=eq.${
      encodeURIComponent(assetId)
    }`,
    {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ is_stale: true, error_code: errorCode }),
    },
  );
}

function quoteFromRow(
  row: LatestQuoteRow,
  stale: boolean,
  errorCode?: string,
): NormalizedQuote {
  return {
    asset_id: String(row.asset_id),
    price: String(row.price),
    currency: row.currency,
    timestamp: Date.parse(row.quoted_at) * 1000,
    fetched_at: row.fetched_at,
    provider: row.provider === "twelve_data"
      ? "twelve_data"
      : row.provider === "coin_gecko"
      ? "coingecko"
      : "brapi",
    stale: stale || row.is_stale,
    refresh_failed: stale || row.is_stale,
    error_code: errorCode ?? row.error_code,
    source: "database",
  };
}

async function reserveCredits(
  provider: DbProvider,
  usage: "scheduled" | "interactive",
  credits: number,
): Promise<boolean> {
  if (!databaseConfigured()) return true;
  return await databaseRequest<boolean>(
    "/rest/v1/rpc/reserve_market_provider_credits",
    {
      method: "POST",
      body: JSON.stringify({
        p_provider: provider,
        p_usage: usage,
        p_credits: credits,
      }),
    },
  );
}

async function providerSettings(
  provider: DbProvider,
  refresh = false,
): Promise<ProviderSettings> {
  if (!refresh && settingsCache.has(provider)) {
    return settingsCache.get(provider)!;
  }
  const rows = await databaseRequest<ProviderSettings[]>(
    `/rest/v1/market_provider_settings?provider=eq.${provider}` +
      "&select=provider,catalog_enabled,persistence_allowed,redistribution_allowed,catalog_cursor&limit=1",
  );
  const settings = rows[0] ?? {
    provider,
    catalog_enabled: false,
    persistence_allowed: false,
    redistribution_allowed: false,
    catalog_cursor: {},
  };
  settingsCache.set(provider, settings);
  return settings;
}

async function saveCatalogCheckpoint(
  provider: DbProvider,
  runId: string,
  cursor: Record<string, unknown>,
  clearProvider = false,
): Promise<void> {
  const persistedCursor = clearProvider ? {} : cursor;
  await databaseRequest(
    `/rest/v1/market_provider_settings?provider=eq.${provider}`,
    {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        catalog_cursor: persistedCursor,
        updated_at: new Date().toISOString(),
      }),
    },
  );
  await databaseRequest(
    `/rest/v1/market_sync_runs?id=eq.${encodeURIComponent(runId)}`,
    {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ cursor }),
    },
  );
  const cached = settingsCache.get(provider);
  if (cached) {
    settingsCache.set(provider, { ...cached, catalog_cursor: persistedCursor });
  }
}

function catalogDisabledReason(settings: ProviderSettings): string | null {
  if (!settings.catalog_enabled) return "catalog_disabled";
  if (!settings.persistence_allowed || !settings.redistribution_allowed) {
    return "persistence_not_approved";
  }
  return null;
}

function activityForPurpose(
  purpose: QuotePurpose,
): "portfolio" | "preview" | "manual_refresh" {
  if (purpose === "portfolio") return "portfolio";
  if (purpose === "preview") return "preview";
  return "manual_refresh";
}

export function nextMarketRefreshAt(
  provider: DbProvider,
  exchange: string,
  success: boolean,
  now = new Date(),
): string {
  if (!success) return new Date(now.getTime() + 60 * 60 * 1000).toISOString();
  if (provider === "coin_gecko") {
    const first = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate(),
      0,
      15,
    ));
    const second = new Date(first);
    second.setUTCHours(12);
    if (first > now) return first.toISOString();
    if (second > now) return second.toISOString();
    first.setUTCDate(first.getUTCDate() + 1);
    return first.toISOString();
  }
  const normalizedExchange = exchange.trim().toUpperCase();
  const targetHour = provider === "brapi" ||
      ["B3", "BVMF"].includes(normalizedExchange)
    ? 21
    : ["NASDAQ", "NYSE", "NYSE ARCA", "AMEX"].includes(normalizedExchange)
    ? 22
    : 23;
  const next = new Date(
    Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate(),
      targetHour,
      15,
    ),
  );
  if (next <= now) {
    next.setUTCDate(next.getUTCDate() + 1);
  }
  return next.toISOString();
}

export function shouldStoreDailyQuote(
  provider: DbProvider,
  exchange: string,
  now = new Date(),
): boolean {
  const minute = now.getUTCHours() * 60 + now.getUTCMinutes();
  if (provider === "coin_gecko") {
    return (minute >= 15 && minute <= 105) ||
      (minute >= 12 * 60 + 15 && minute <= 13 * 60 + 45);
  }
  const normalizedExchange = exchange.trim().toUpperCase();
  const closeMinute = provider === "brapi" ||
      ["B3", "BVMF"].includes(normalizedExchange)
    ? 21 * 60 + 15
    : ["NASDAQ", "NYSE", "NYSE ARCA", "AMEX"].includes(normalizedExchange)
    ? 22 * 60 + 15
    : 23 * 60 + 15;
  return minute >= closeMinute;
}

export function restoreBrapiCheckpoint(
  cursor: Record<string, unknown>,
  assetCount: number,
): { offset: number; metrics: Record<string, number> } {
  if (
    cursor.stage !== "brapi_ranking" ||
    Number(cursor.asset_count) !== assetCount ||
    !Number.isInteger(Number(cursor.offset)) ||
    Number(cursor.offset) < 0 || Number(cursor.offset) > assetCount ||
    !isRecord(cursor.metrics)
  ) {
    return { offset: 0, metrics: {} };
  }
  const metrics: Record<string, number> = {};
  for (const [symbol, score] of Object.entries(cursor.metrics)) {
    const parsed = Number(score);
    if (symbol && Number.isFinite(parsed) && parsed >= 0) {
      metrics[symbol] = parsed;
    }
  }
  return { offset: Number(cursor.offset), metrics };
}

export function restoreTwelveDataCheckpoint(
  cursor: Record<string, unknown>,
  pageSize = TWELVE_DATA_CATALOG_PAGE_SIZE,
  fallbackCycleRunId = "1",
): TwelveDataCatalogCheckpoint {
  const nextPage = Number(cursor.next_page);
  const imported = Number(cursor.imported);
  const discovered = Number(cursor.discovered);
  const cycleRunId = String(cursor.cycle_run_id ?? "");
  if (
    cursor.stage !== "twelve_catalog" ||
    Number(cursor.cursor_version) !== 2 ||
    Number(cursor.page_size) !== pageSize ||
    !Number.isInteger(nextPage) || nextPage < 0 ||
    !Number.isInteger(imported) || imported < 0 ||
    !Number.isInteger(discovered) || discovered < 0 ||
    !/^[1-9]\d*$/.test(cycleRunId)
  ) {
    return {
      nextPage: 0,
      imported: 0,
      discovered: 0,
      cycleRunId: fallbackCycleRunId,
    };
  }
  return { nextPage, imported, discovered, cycleRunId };
}

export function twelveDataCatalogUrl(
  token: string,
  page: number,
  pageSize = TWELVE_DATA_CATALOG_PAGE_SIZE,
): URL {
  if (!Number.isInteger(page) || page < 0) {
    throw new MarketDataError("invalid_catalog_page", 500);
  }
  if (!Number.isInteger(pageSize) || pageSize < 1) {
    throw new MarketDataError("invalid_catalog_page_size", 500);
  }
  const url = new URL("https://api.twelvedata.com/stocks");
  url.searchParams.set("page", String(page));
  url.searchParams.set("outputsize", String(pageSize));
  url.searchParams.set("apikey", token);
  return url;
}

export function isTwelveDataCatalogPageComplete(
  rowCount: number,
  pageSize = TWELVE_DATA_CATALOG_PAGE_SIZE,
): boolean {
  return Number.isInteger(rowCount) && rowCount >= 0 && rowCount < pageSize;
}

function candidateFromCatalogRow(
  row: Record<string, unknown>,
): SearchCandidate {
  const provider = fromDbProvider(String(row.provider) as DbProvider);
  return {
    asset_id: String(row.asset_id),
    symbol: String(row.symbol),
    name: String(row.name),
    asset_class: String(row.asset_class),
    currency: String(row.currency),
    exchange: row.exchange ? String(row.exchange) : null,
    provider,
    provider_symbol: String(row.provider_symbol),
    relevance_score: Number(row.relevance_score ?? 0),
  };
}

function brapiCatalogCandidate(
  row: Record<string, unknown>,
): SearchCandidate | null {
  const symbol = String(row.symbol ?? row.stock ?? "").trim().toUpperCase();
  const name = String(row.longName ?? row.name ?? row.shortName ?? symbol)
    .trim();
  if (!symbol || !name) return null;
  return {
    symbol,
    name,
    asset_class: brapiClass(
      String(row.subType ?? row.type ?? ""),
      String(row.assetType ?? ""),
    ),
    currency: String(row.currency ?? "BRL").toUpperCase(),
    exchange: String(row.exchange ?? "B3").toUpperCase(),
    country: "Brazil",
    provider: "brapi",
    provider_symbol: symbol,
  };
}

function twelveCatalogCandidate(
  row: Record<string, unknown>,
): SearchCandidate | null {
  const symbol = String(row.symbol ?? "").trim().toUpperCase();
  const name = String(row.name ?? row.instrument_name ?? symbol).trim();
  const currency = String(row.currency ?? "").trim().toUpperCase();
  const rawType = String(row.type ?? row.instrument_type ?? "");
  const assetClass = twelveCatalogClass(rawType);
  if (
    !symbol || !name || !/^[A-Z]{3}$/.test(currency) ||
    assetClass == null
  ) {
    return null;
  }
  return {
    symbol,
    name,
    asset_class: assetClass,
    currency,
    exchange: String(row.exchange ?? row.mic_code ?? "").toUpperCase() || null,
    mic_code: String(row.mic_code ?? "").toUpperCase() || null,
    country: String(row.country ?? "") || null,
    isin: normalizeIsin(row.isin),
    provider: "twelveData",
    provider_symbol: symbol,
  };
}

export function normalizeIsin(value: unknown): string | null {
  const normalized = String(value ?? "").trim().toUpperCase();
  return /^[A-Z]{2}[A-Z0-9]{9}[0-9]$/.test(normalized) ? normalized : null;
}

function brapiClass(subType: string, assetType: string): string {
  const normalized = `${subType} ${assetType}`.toLowerCase();
  if (normalized.includes("fii")) return "fii";
  if (normalized.includes("etf")) return "etf";
  if (normalized.includes("reit")) return "reit";
  if (normalized.includes("fund")) return "fund";
  return "stock";
}

function twelveDataClass(type: string, fallback: string): string {
  const normalized = type.toLowerCase();
  if (normalized.includes("etf")) return "etf";
  if (normalized.includes("reit")) return "reit";
  if (normalized.includes("mutual") || normalized.includes("fund")) {
    return "fund";
  }
  if (normalized.includes("bond")) return "bond";
  if (normalized.includes("commod")) return "commodity";
  if (
    normalized.includes("stock") || normalized.includes("equity") ||
    normalized.includes("common") || normalized.includes("preferred") ||
    normalized.includes("depositary")
  ) return "stock";
  return SUPPORTED_ASSET_CLASSES.has(fallback) ? fallback : "other";
}

function twelveCatalogClass(type: string): string | null {
  const normalized = type.toLowerCase();
  if (
    normalized.includes("forex") || normalized.includes("currency") ||
    normalized.includes("crypto") || normalized.includes("index")
  ) return null;
  const mapped = twelveDataClass(type, "");
  return mapped === "other" ? null : mapped;
}

function validCandidate(value: SearchCandidate): boolean {
  return value.symbol.length > 0 && value.name.length > 0 &&
    value.provider_symbol.length > 0 && /^[A-Z]{3}$/.test(value.currency) &&
    SUPPORTED_ASSET_CLASSES.has(value.asset_class);
}

function positiveDecimal(value: unknown): string {
  const text = String(value ?? "");
  if (
    !/^(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(text) ||
    Number(text) <= 0
  ) {
    throw new MarketDataError("invalid_provider_response");
  }
  return text;
}

async function checked(
  response: Response,
  maximumBytes?: number,
): Promise<string> {
  const body = maximumBytes == null
    ? await response.text()
    : await readBoundedResponseText(response, maximumBytes);
  if (!response.ok) {
    const code = response.status === 429
      ? "rate_limited"
      : `provider_http_${response.status}`;
    throw new MarketDataError(code, response.status === 429 ? 429 : 502);
  }
  return body;
}

export async function withProviderTimeout<T>(
  operation: (signal: AbortSignal) => Promise<T>,
  timeoutMs = PROVIDER_FETCH_TIMEOUT_MS,
): Promise<T> {
  const controller = new AbortController();
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const timeoutResult = new Promise<never>((_resolve, reject) => {
    timeout = setTimeout(() => {
      controller.abort();
      reject(new MarketDataError("provider_timeout", 504));
    }, timeoutMs);
  });
  try {
    return await Promise.race([operation(controller.signal), timeoutResult]);
  } catch (error) {
    if (
      controller.signal.aborted &&
      !(error instanceof MarketDataError && error.code === "provider_timeout")
    ) {
      throw new MarketDataError("provider_timeout", 504);
    }
    throw error;
  } finally {
    if (timeout != null) clearTimeout(timeout);
  }
}

export async function readBoundedResponseText(
  response: Response,
  maximumBytes: number,
): Promise<string> {
  if (!Number.isInteger(maximumBytes) || maximumBytes < 1) {
    throw new MarketDataError("invalid_response_size_limit", 500);
  }
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new MarketDataError("provider_response_too_large");
  }
  if (!response.body) return "";
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  let result = "";
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > maximumBytes) {
        await reader.cancel();
        throw new MarketDataError("provider_response_too_large");
      }
      result += decoder.decode(chunk.value, { stream: true });
    }
    return result + decoder.decode();
  } finally {
    reader.releaseLock();
  }
}

async function checkedJson(
  response: Response,
  maximumBytes?: number,
): Promise<Record<string, unknown>> {
  const value: unknown = JSON.parse(await checked(response, maximumBytes));
  if (!isRecord(value)) throw new MarketDataError("invalid_provider_response");
  if (String(value.status ?? "").toLowerCase() === "error") {
    throw new MarketDataError(String(value.code ?? "provider_unavailable"));
  }
  return value;
}

async function checkedJsonArray(response: Response): Promise<unknown[]> {
  const value: unknown = JSON.parse(await checked(response));
  if (!Array.isArray(value)) {
    throw new MarketDataError("invalid_provider_response");
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

async function databaseRequest<T = unknown>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new MarketDataError("database_not_configured", 503);
  let response: Response;
  try {
    response = await fetch(`${url.replace(/\/$/, "")}${path}`, {
      ...init,
      headers: {
        "content-type": "application/json",
        apikey: key,
        authorization: `Bearer ${key}`,
        ...(init.headers ?? {}),
      },
    });
  } catch {
    throw new MarketDataError("database_network", 503);
  }
  if (!response.ok) {
    throw new MarketDataError(`database_${response.status}`, 503);
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}
