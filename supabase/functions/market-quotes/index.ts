import {
  candidateScore,
  catalogReadEnabled,
  deduplicateCandidates,
  type HeartbeatRequest,
  MarketDataError,
  type NormalizedQuote,
  persistCandidates,
  type Provider,
  providerErrorCode,
  type QuotePurpose,
  type QuoteRequest,
  quoteWithCache,
  renewTargets,
  type SearchCandidate,
  searchCatalog,
  searchProviders,
  type SearchRequest,
} from "../_shared/market_data.ts";

const limits = new Map<string, { window: number; count: number }>();
const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!allow(identityFor(request))) return json({ error: "rate_limited" }, 429);

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  try {
    const search = parseSearchRequest(raw);
    if (search) return await handleSearch(search);
    const heartbeat = parseHeartbeatRequest(raw);
    if (heartbeat) return await handleHeartbeat(heartbeat);
    const quote = parseQuoteRequest(raw);
    if (quote) return json(publicQuote(await quoteWithCache(quote)));
    return json({ error: "invalid_market_request" }, 400);
  } catch (error) {
    const code = providerErrorCode(error);
    const status = error instanceof MarketDataError ? error.status : 502;
    return json({ error: code }, status);
  }
});

async function handleSearch(input: SearchRequest): Promise<Response> {
  const limit = Math.min(Math.max(input.limit ?? 10, 1), 10);
  let catalog: SearchCandidate[] = [];
  try {
    catalog = await searchCatalog(input);
  } catch {
    // Catalog rollout and provider availability are isolated from each other.
  }
  if (catalog.length >= limit) {
    const results = catalog.slice(0, limit);
    await activateSearchResults(results);
    return json({
      results: results.map(publicCandidate),
      failed_providers: [],
      source: "catalog",
    });
  }

  const upstream = await searchProviders(input);
  let providerResults = upstream.results;
  if (catalogReadEnabled() && providerResults.length > 0) {
    try {
      providerResults = await persistCandidates(providerResults);
      const refreshed = await searchCatalog(input);
      if (refreshed.length > 0) catalog = refreshed;
    } catch {
      // Search still returns provider results when catalog persistence is unavailable.
    }
  }
  const results = deduplicateCandidates([...catalog, ...providerResults])
    .sort((left, right) =>
      candidateScore(right, input) - candidateScore(left, input)
    )
    .slice(0, limit);
  await activateSearchResults(results);
  if (
    results.length === 0 &&
    upstream.failed.length === searchProvidersCount(input.asset_class)
  ) {
    return json({
      error: "provider_unavailable",
      failed_providers: upstream.failed,
    }, 502);
  }
  return json({
    results: results.map(publicCandidate),
    failed_providers: upstream.failed,
    source: catalog.length > 0 ? "catalog_and_provider" : "provider",
  });
}

async function activateSearchResults(
  results: SearchCandidate[],
): Promise<void> {
  if (!catalogReadEnabled() || results.length === 0) return;
  try {
    await renewTargets(
      results.map((asset) => ({
        provider: asset.provider,
        provider_symbol: asset.provider_symbol,
        currency: asset.currency,
        exchange: asset.exchange,
      })),
      "preview",
    );
  } catch {
    // Search remains available while activation is best effort.
  }
}

async function handleHeartbeat(input: HeartbeatRequest): Promise<Response> {
  const accepted = await renewTargets(input.assets, "portfolio");
  return json({ accepted });
}

function parseSearchRequest(value: unknown): SearchRequest | null {
  if (!isRecord(value) || value.operation !== "search") return null;
  const query = String(value.query ?? "").trim();
  const assetClass = String(value.asset_class ?? value.assetClass ?? "");
  const currency = String(value.currency ?? "").toUpperCase();
  const limit = value.limit === undefined ? 10 : Number(value.limit);
  if (
    query.length < 2 || query.length > 80 || !assetClass ||
    !/^[A-Z]{3}$/.test(currency) || !Number.isInteger(limit) || limit < 1
  ) {
    return null;
  }
  return {
    operation: "search",
    query,
    asset_class: assetClass,
    currency,
    limit: Math.min(limit, 10),
  };
}

function parseQuoteRequest(value: unknown): QuoteRequest | null {
  if (
    !isRecord(value) ||
    (value.operation !== undefined && value.operation !== "quote")
  ) return null;
  const provider = String(value.provider ?? "") as Provider;
  const symbol = String(value.symbol ?? "").trim();
  const providerSymbol = String(
    value.provider_symbol ?? value.providerSymbol ?? symbol,
  ).trim();
  const currency = String(value.currency ?? "").toUpperCase();
  const assetClass = String(value.asset_class ?? value.assetClass ?? "");
  const purpose = String(value.purpose ?? "manualRefresh") as QuotePurpose;
  if (
    !["brapi", "twelveData", "coinGecko"].includes(provider) ||
    !/^[0-9A-Za-z._:^=\-/]{1,160}$/.test(providerSymbol) ||
    !/^[A-Z]{3}$/.test(currency) || !assetClass ||
    !["portfolio", "preview", "manualRefresh"].includes(purpose)
  ) {
    return null;
  }
  return {
    operation: "quote",
    asset_id: nullableString(value.asset_id ?? value.assetId),
    provider,
    instrument_id: nullableString(value.instrument_id),
    symbol: symbol || providerSymbol,
    provider_symbol: providerSymbol,
    asset_class: assetClass,
    currency,
    exchange: nullableString(value.exchange),
    purpose,
  };
}

function parseHeartbeatRequest(value: unknown): HeartbeatRequest | null {
  if (
    !isRecord(value) || value.operation !== "heartbeat" ||
    !Array.isArray(value.assets) ||
    value.assets.length < 1 || value.assets.length > 200
  ) return null;
  const assets: HeartbeatRequest["assets"] = [];
  for (const item of value.assets) {
    if (!isRecord(item)) return null;
    const provider = String(item.provider ?? "") as Provider;
    const providerSymbol = String(
      item.provider_symbol ?? item.providerSymbol ?? "",
    ).trim();
    const currency = String(item.currency ?? "").toUpperCase();
    if (
      !["brapi", "twelveData", "coinGecko"].includes(provider) ||
      !/^[0-9A-Za-z._:^=\-/]{1,160}$/.test(providerSymbol) ||
      !/^[A-Z]{3}$/.test(currency)
    ) return null;
    assets.push({
      provider,
      provider_symbol: providerSymbol,
      currency,
      exchange: nullableString(item.exchange),
    });
  }
  return { operation: "heartbeat", assets };
}

function publicCandidate(value: SearchCandidate): Record<string, unknown> {
  return {
    assetId: value.asset_id ?? null,
    symbol: value.symbol,
    name: value.name,
    assetClass: value.asset_class,
    currency: value.currency,
    exchange: value.exchange,
    provider: value.provider,
    providerSymbol: value.provider_symbol,
    // Backward compatibility for v1.1.0 clients deployed before the catalog.
    asset_class: value.asset_class,
    provider_symbol: value.provider_symbol,
  };
}

function publicQuote(value: NormalizedQuote): Record<string, unknown> {
  return {
    ...value,
    assetId: value.asset_id ?? null,
    fetchedAt: value.fetched_at ?? null,
    refreshFailed: value.refresh_failed ?? false,
    errorCode: value.error_code ?? null,
  };
}

function searchProvidersCount(assetClass: string): number {
  if (assetClass === "crypto" || assetClass === "fii") return 1;
  if (["stock", "etf", "fund", "reit"].includes(assetClass)) return 2;
  return 1;
}

function identityFor(request: Request): string {
  const token = (request.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  const parts = token.split(".");
  if (parts.length === 3) {
    try {
      const segment = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      const payload = JSON.parse(
        atob(segment.padEnd(Math.ceil(segment.length / 4) * 4, "=")),
      );
      if (typeof payload.sub === "string" && payload.sub.length > 0) {
        return `sub:${payload.sub}`;
      }
    } catch {
      // The Supabase gateway validates JWTs; non-user keys fall back to IP.
    }
  }
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]
    ?.trim();
  return `ip:${
    forwarded || request.headers.get("cf-connecting-ip") || "unknown"
  }`;
}

function allow(identity: string): boolean {
  const window = Math.floor(Date.now() / 60_000);
  const current = limits.get(identity);
  if (!current || current.window !== window) {
    limits.set(identity, { window, count: 1 });
    return true;
  }
  if (current.count >= 60) return false;
  current.count += 1;
  return true;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function nullableString(value: unknown): string | null {
  const text = String(value ?? "").trim();
  return text || null;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}
