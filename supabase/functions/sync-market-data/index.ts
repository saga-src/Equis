import {
  claimRefreshTargets,
  completeRefreshTarget,
  createSyncRun,
  type DbProvider,
  finishSyncRun,
  providerErrorCode,
  pruneMarketData,
  refreshTrackedTarget,
  scheduledQuotesEnabled,
  syncBrapiCatalog,
  syncCoinGeckoCatalog,
  syncTwelveDataCatalog,
} from "../_shared/market_data.ts";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-equis-sync-secret",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const configuredSecret = Deno.env.get("MARKET_SYNC_SECRET") ?? "";
  const providedSecret = request.headers.get("x-equis-sync-secret") ?? "";
  if (
    !configuredSecret || !(await secretsEqual(configuredSecret, providedSecret))
  ) {
    return json({ error: "unauthorized" }, 401);
  }

  let input: unknown;
  try {
    input = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (
    !isRecord(input) ||
    !["catalog", "quotes", "cleanup"].includes(String(input.operation))
  ) {
    return json({ error: "invalid_sync_request" }, 400);
  }

  try {
    if (input.operation === "catalog") return json(await syncCatalog());
    if (input.operation === "quotes") return json(await syncQuotes());
    return json(await cleanup());
  } catch (error) {
    return json({ error: providerErrorCode(error) }, 502);
  }
});

async function syncCatalog(): Promise<Record<string, unknown>> {
  const jobs = [
    ["brapi", syncBrapiCatalog],
    ["twelve_data", syncTwelveDataCatalog],
    ["coin_gecko", syncCoinGeckoCatalog],
  ] as const;
  const providers: Record<string, unknown> = {};
  const failed: string[] = [];
  for (const [provider, job] of jobs) {
    try {
      providers[provider] = await job();
    } catch (error) {
      providers[provider] = { error: providerErrorCode(error) };
      failed.push(provider);
    }
  }
  return { operation: "catalog", providers, failed_providers: failed };
}

async function syncQuotes(): Promise<Record<string, unknown>> {
  const runId = await createSyncRun("system", "quotes");
  if (!scheduledQuotesEnabled()) {
    await finishSyncRun(
      runId,
      "disabled",
      { claimed: 0 },
      "scheduled_quotes_disabled",
    );
    return { operation: "quotes", disabled: true, claimed: 0 };
  }
  const targets = await claimRefreshTargets(100);
  const byProvider = new Map<DbProvider, typeof targets>();
  for (const target of targets) {
    const group = byProvider.get(target.provider) ?? [];
    group.push(target);
    byProvider.set(target.provider, group);
  }
  let updated = 0;
  let stale = 0;
  let failed = 0;
  await Promise.all([...byProvider.values()].map(async (providerTargets) => {
    let rateLimited = false;
    for (const target of providerTargets) {
      if (rateLimited) {
        failed += 1;
        await completeRefreshTarget(target, false, "rate_limited");
        continue;
      }
      try {
        const quote = await refreshTrackedTarget(target);
        if (quote.refresh_failed || quote.stale) {
          stale += 1;
          const code = quote.error_code ?? "provider_unavailable";
          if (code === "rate_limited") rateLimited = true;
          await completeRefreshTarget(target, false, code);
        } else {
          updated += 1;
          await completeRefreshTarget(target, true);
        }
      } catch (error) {
        failed += 1;
        const code = providerErrorCode(error);
        if (code === "rate_limited") rateLimited = true;
        await completeRefreshTarget(target, false, code);
      }
    }
  }));
  const status = failed === 0 && stale === 0 ? "completed" : "partial";
  const counters = { claimed: targets.length, updated, stale, failed };
  await finishSyncRun(runId, status, counters);
  return { operation: "quotes", ...counters };
}

async function cleanup(): Promise<Record<string, unknown>> {
  const runId = await createSyncRun("system", "cleanup");
  try {
    const counters = await pruneMarketData();
    await finishSyncRun(runId, "completed", counters);
    return { operation: "cleanup", ...counters };
  } catch (error) {
    await finishSyncRun(runId, "failed", {}, providerErrorCode(error));
    throw error;
  }
}

async function secretsEqual(
  expected: string,
  provided: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}
