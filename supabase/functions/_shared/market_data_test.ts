import {
  candidateScore,
  canonicalAssetKey,
  deduplicateCandidates,
  isTwelveDataCatalogPageComplete,
  MarketDataError,
  nextMarketRefreshAt,
  normalizeIsin,
  normalizeProviderSymbol,
  readBoundedResponseText,
  restoreBrapiCheckpoint,
  restoreTwelveDataCheckpoint,
  type SearchCandidate,
  type SearchRequest,
  shouldStoreDailyQuote,
  twelveDataCatalogUrl,
  withProviderTimeout,
} from "./market_data.ts";

const crypto: SearchCandidate = {
  symbol: "BTC",
  name: "Bitcoin",
  asset_class: "crypto",
  currency: "BRL",
  exchange: null,
  provider: "coinGecko",
  provider_symbol: "bitcoin",
};

Deno.test("canonical crypto identity uses CoinGecko id and quote currency", () => {
  if (canonicalAssetKey(crypto) !== "crypto:coingecko:bitcoin:BRL") {
    throw new Error("unexpected crypto identity");
  }
  if (normalizeProviderSymbol("coinGecko", "BitCoin") !== "bitcoin") {
    throw new Error("CoinGecko identifiers must remain lowercase");
  }
});

Deno.test("security identity keeps exchange and currency distinct", () => {
  const base: SearchCandidate = {
    symbol: "ABC",
    name: "Acme",
    asset_class: "stock",
    currency: "USD",
    exchange: "NASDAQ",
    provider: "twelveData",
    provider_symbol: "ABC",
  };
  const other = { ...base, exchange: "NYSE" };
  if (canonicalAssetKey(base) === canonicalAssetKey(other)) {
    throw new Error("different listings were merged");
  }
  if (deduplicateCandidates([base, other]).length !== 2) {
    throw new Error("different exchanges were deduplicated");
  }
});

Deno.test("exact symbol outranks provider relevance", () => {
  const input: SearchRequest = {
    operation: "search",
    query: "AAPL",
    asset_class: "stock",
    currency: "USD",
    limit: 10,
  };
  const exact: SearchCandidate = {
    symbol: "AAPL",
    name: "Apple Inc",
    asset_class: "stock",
    currency: "USD",
    exchange: "NASDAQ",
    provider: "twelveData",
    provider_symbol: "AAPL",
    relevance_score: 1,
  };
  const popular = {
    ...exact,
    symbol: "AAPLD",
    provider_symbol: "AAPLD",
    relevance_score: 9000,
  };
  if (candidateScore(exact, input) <= candidateScore(popular, input)) {
    throw new Error("exact match must win");
  }
});

Deno.test("BRAPI ranking resumes only a compatible checkpoint", () => {
  const resumed = restoreBrapiCheckpoint({
    stage: "brapi_ranking",
    asset_count: 100,
    offset: 40,
    metrics: { PETR4: 12.5, INVALID: "ignored" },
  }, 100);
  if (resumed.offset !== 40 || resumed.metrics.PETR4 !== 12.5) {
    throw new Error("valid ranking checkpoint was not restored");
  }
  if ("INVALID" in resumed.metrics) {
    throw new Error("invalid checkpoint metric was accepted");
  }
  const reset = restoreBrapiCheckpoint({
    stage: "brapi_ranking",
    asset_count: 99,
    offset: 40,
    metrics: { PETR4: 12.5 },
  }, 100);
  if (reset.offset !== 0 || Object.keys(reset.metrics).length !== 0) {
    throw new Error("incompatible ranking checkpoint was not reset");
  }
});

Deno.test("Twelve Data catalog resumes the same paged sync cycle", () => {
  const resumed = restoreTwelveDataCheckpoint(
    {
      stage: "twelve_catalog",
      cursor_version: 2,
      page_size: 1000,
      next_page: 6,
      imported: 4321,
      discovered: 5000,
      cycle_run_id: "42",
    },
    1000,
    "99",
  );
  if (
    resumed.nextPage !== 6 || resumed.imported !== 4321 ||
    resumed.discovered !== 5000 || resumed.cycleRunId !== "42"
  ) {
    throw new Error("valid Twelve Data checkpoint was not restored");
  }
  const reset = restoreTwelveDataCheckpoint(
    {
      stage: "twelve_catalog",
      cursor_version: 2,
      page_size: 500,
      next_page: 6,
      imported: 2500,
      discovered: 2500,
      cycle_run_id: "42",
    },
    1000,
    "99",
  );
  if (
    reset.nextPage !== 0 || reset.imported !== 0 ||
    reset.discovered !== 0 || reset.cycleRunId !== "99"
  ) {
    throw new Error("incompatible Twelve Data checkpoint was not reset");
  }
});

Deno.test("Twelve Data catalog only completes on a short final page", () => {
  if (isTwelveDataCatalogPageComplete(1000, 1000)) {
    throw new Error("a full page was treated as the end of the catalog");
  }
  if (!isTwelveDataCatalogPageComplete(317, 1000)) {
    throw new Error("a short page did not complete the catalog");
  }
});

Deno.test("Twelve Data catalog request is always explicitly paged", () => {
  const url = twelveDataCatalogUrl("test-key", 0, 1000);
  if (
    url.pathname !== "/stocks" || url.searchParams.get("page") !== "0" ||
    url.searchParams.get("outputsize") !== "1000" ||
    url.searchParams.has("show_plan")
  ) {
    throw new Error("Twelve Data catalog request lost its page bounds");
  }
});

Deno.test("Twelve Data invalid ISIN metadata is ignored", () => {
  if (normalizeIsin("US0378331005") !== "US0378331005") {
    throw new Error("valid ISIN was discarded");
  }
  if (normalizeIsin("N/A") !== null || normalizeIsin("") !== null) {
    throw new Error("invalid ISIN was persisted");
  }
});

Deno.test("provider timeout aborts a stalled catalog request", async () => {
  try {
    await withProviderTimeout(
      () => new Promise<void>(() => {}),
      5,
    );
    throw new Error("stalled provider request did not time out");
  } catch (error) {
    if (
      !(error instanceof MarketDataError) || error.code !== "provider_timeout"
    ) {
      throw error;
    }
  }
});

Deno.test("bounded provider response rejects an oversized payload", async () => {
  try {
    await readBoundedResponseText(new Response("12345"), 4);
    throw new Error("oversized provider response was accepted");
  } catch (error) {
    if (
      !(error instanceof MarketDataError) ||
      error.code !== "provider_response_too_large"
    ) {
      throw error;
    }
  }
  const accepted = await readBoundedResponseText(new Response("12345"), 5);
  if (accepted !== "12345") {
    throw new Error("bounded provider response changed valid content");
  }
});

Deno.test("scheduled quotes use close windows and fixed crypto snapshots", () => {
  const morning = new Date("2026-09-22T01:00:00.000Z");
  if (
    nextMarketRefreshAt("coin_gecko", "", true, morning) !==
      "2026-09-22T12:15:00.000Z"
  ) {
    throw new Error("crypto did not select the 12:15 UTC snapshot");
  }
  const afternoon = new Date("2026-09-22T13:00:00.000Z");
  if (
    nextMarketRefreshAt("coin_gecko", "", true, afternoon) !==
      "2026-09-23T00:15:00.000Z"
  ) {
    throw new Error("crypto did not roll to the next 00:15 UTC snapshot");
  }
  if (shouldStoreDailyQuote("brapi", "B3", morning)) {
    throw new Error("B3 intraday quote was treated as a daily close");
  }
  if (
    !shouldStoreDailyQuote(
      "brapi",
      "B3",
      new Date("2026-09-22T21:15:00.000Z"),
    )
  ) {
    throw new Error("B3 post-close quote was not stored daily");
  }
});
