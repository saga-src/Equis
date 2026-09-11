type Provider = "brapi" | "twelveData" | "coinGecko";
type QuoteRequest = {
  provider: Provider;
  instrument_id: string;
  symbol: string;
  provider_symbol?: string | null;
  asset_class: string;
  currency: string;
  exchange?: string | null;
};
type NormalizedQuote = { price: string; currency: string; timestamp: number; provider: string };

const cache = new Map<string, { expires: number; value: NormalizedQuote }>();
const limits = new Map<string, { window: number; count: number }>();
const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, apikey, content-type" };

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const identity = request.headers.get("authorization") ?? "anonymous";
  if (!allow(identity)) return json({ error: "rate_limited" }, 429);
  let input: QuoteRequest;
  try { input = await request.json(); } catch { return json({ error: "invalid_json" }, 400); }
  if (!valid(input)) return json({ error: "invalid_quote_request" }, 400);
  const key = `${input.provider}|${input.provider_symbol ?? input.symbol}|${input.currency}`;
  const cached = cache.get(key);
  if (cached && cached.expires > Date.now()) return json(cached.value, 200, { "x-equis-cache": "hit" });
  try {
    const value = await fetchProvider(input);
    cache.set(key, { expires: Date.now() + 60_000, value });
    return json(value, 200, { "x-equis-cache": "miss" });
  } catch (error) {
    return json({ error: "provider_unavailable", provider: input.provider,
      detail: error instanceof Error ? error.message : "unknown" }, 502);
  }
});

function valid(value: QuoteRequest): boolean {
  return value && ["brapi", "twelveData", "coinGecko"].includes(value.provider) &&
    /^[0-9A-Za-z._:^=-]{1,80}$/.test(value.provider_symbol ?? value.symbol) &&
    /^[A-Z]{3}$/.test(value.currency) && typeof value.instrument_id === "string" &&
    value.instrument_id.length <= 64 && typeof value.asset_class === "string";
}

function allow(identity: string): boolean {
  const now = Date.now(), window = Math.floor(now / 60_000);
  const current = limits.get(identity);
  if (!current || current.window !== window) { limits.set(identity, { window, count: 1 }); return true; }
  if (current.count >= 60) return false;
  current.count += 1; return true;
}

async function fetchProvider(input: QuoteRequest): Promise<NormalizedQuote> {
  if (input.provider === "brapi") return brapi(input);
  if (input.provider === "coinGecko") return coinGecko(input);
  return twelveData(input);
}

async function brapi(input: QuoteRequest): Promise<NormalizedQuote> {
  const symbol = input.provider_symbol ?? input.symbol;
  const url = new URL("https://brapi.dev/api/v2/stocks/quote");
  url.searchParams.set("symbols", symbol);
  const token = Deno.env.get("BRAPI_API_TOKEN");
  const response = await fetch(url, { headers: token ? { authorization: `Bearer ${token}` } : {} });
  const body = await checked(response);
  const price = capture(body, /"regularMarketPrice"\s*:\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)/);
  const currency = capture(body, /"currency"\s*:\s*"([A-Z]{3})"/);
  const time = /"regularMarketTime"\s*:\s*"([^"]+)"/.exec(body)?.[1];
  return { price, currency, timestamp: time ? Date.parse(time) * 1000 : Date.now() * 1000, provider: "brapi" };
}

async function twelveData(input: QuoteRequest): Promise<NormalizedQuote> {
  const url = new URL("https://api.twelvedata.com/price");
  url.searchParams.set("symbol", input.provider_symbol ?? input.symbol);
  if (input.exchange) url.searchParams.set("exchange", input.exchange);
  const token = Deno.env.get("TWELVE_DATA_API_KEY");
  if (!token) throw new Error("twelve_data_not_configured");
  url.searchParams.set("apikey", token);
  const body = await checked(await fetch(url));
  const price = capture(body, /"price"\s*:\s*"([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)"/);
  return { price, currency: input.currency, timestamp: Date.now() * 1000, provider: "twelve_data" };
}

async function coinGecko(input: QuoteRequest): Promise<NormalizedQuote> {
  const id = input.provider_symbol ?? input.symbol;
  const currency = input.currency.toLowerCase();
  const url = new URL("https://api.coingecko.com/api/v3/simple/price");
  url.searchParams.set("ids", id); url.searchParams.set("vs_currencies", currency);
  url.searchParams.set("include_last_updated_at", "true"); url.searchParams.set("precision", "full");
  const token = Deno.env.get("COINGECKO_API_KEY");
  const body = await checked(await fetch(url, { headers: token ? { "x-cg-demo-api-key": token } : {} }));
  const escaped = currency.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const price = capture(body, new RegExp(`"${escaped}"\\s*:\\s*([-+]?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)`));
  const updated = /"last_updated_at"\s*:\s*(\d+)/.exec(body)?.[1];
  return { price, currency: input.currency, timestamp: updated ? Number(updated) * 1_000_000 : Date.now() * 1000, provider: "coingecko" };
}

async function checked(response: Response): Promise<string> {
  const body = await response.text();
  if (!response.ok) throw new Error(`http_${response.status}`);
  return body;
}
function capture(body: string, pattern: RegExp): string {
  const value = pattern.exec(body)?.[1]; if (!value) throw new Error("invalid_provider_response"); return value;
}
function json(value: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(value), { status, headers: { ...cors, ...extra, "content-type": "application/json" } });
}
