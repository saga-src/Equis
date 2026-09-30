import {
  collectionWindow,
  type CollectorPorts,
  collectSeries,
  EconomicSeriesError,
  fetchSgsPage,
  normalizeUtcTimestamp,
  ORIGINAL_SOURCE,
  parseReadRequest,
  parseSgsPage,
  recentWindow,
  SERIES,
  SERIES_CODES,
  sgsUrl,
  shouldSeedRecent,
  staleDays,
} from "./economic_series.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function raises(code: string, body: () => unknown): void {
  try {
    body();
  } catch (error) {
    assert(
      error instanceof EconomicSeriesError && error.code === code,
      `expected ${code}, got ${String(error)}`,
    );
    return;
  }
  throw new Error(`expected ${code}`);
}

Deno.test("all six SGS codes have explicit distinct units", () => {
  assert(SERIES_CODES.length === 6, "missing SGS code");
  assert(
    SERIES[11] === "percent_per_day" &&
      SERIES[12] === "percent_per_day",
    "daily rates mislabelled",
  );
  assert(
    [188, 189, 433].every((code) =>
      SERIES[code as 188 | 189 | 433] === "percent_per_month"
    ),
    "monthly rates mislabelled",
  );
  assert(SERIES[226] === "percent_per_validity_period", "TR mislabelled");
  assert(ORIGINAL_SOURCE[189] === "FGV IBRE", "IGP-M origin lost");
});

Deno.test("database timestamps are normalized to UTC Z", () => {
  assert(
    normalizeUtcTimestamp("2026-09-24T10:00:00+00:00") ===
      "2026-09-24T10:00:00.000Z",
    "PostgREST timestamp was not normalized",
  );
});

Deno.test("TR preserves dataFim validity and rejects absent or inverted period", () => {
  const window = { from: "2026-09-01", through: "2026-09-30" };
  const [tr] = parseSgsPage(
    226,
    [
      { data: "01/09/2026", dataFim: "01/10/2026", valor: "0,1234" },
    ],
    "2026-09-24T10:00:00.000Z",
    window,
  );
  assert(
    tr.reference_start === "2026-09-01" &&
      tr.reference_end === "2026-10-01" && tr.value === "0.1234",
    "TR period or value changed",
  );
  assert(
    staleDays(tr.reference_start, "2026-09-24") === 23,
    "future TR validity masked missing daily observations",
  );
  raises(
    "invalid_sgs_payload",
    () =>
      parseSgsPage(
        226,
        [{ data: "01/09/2026", valor: "0,1234" }],
        "2026-09-24T10:00:00.000Z",
        window,
      ),
  );
  raises(
    "invalid_sgs_payload",
    () =>
      parseSgsPage(
        226,
        [{ data: "01/09/2026", dataFim: "31/08/2026", valor: "0,1234" }],
        "2026-09-24T10:00:00.000Z",
        window,
      ),
  );
});

Deno.test("monthly deflation keeps its sign and calendar month", () => {
  const [ipca] = parseSgsPage(
    433,
    [
      { data: "01/02/2024", valor: "-0,25" },
    ],
    "2024-03-01T10:00:00.000Z",
    { from: "2024-02-01", through: "2024-02-29" },
  );
  assert(
    ipca.reference_start === "2024-02-01" &&
      ipca.reference_end === "2024-02-29" && ipca.value === "-0.25",
    "monthly reference or deflation changed",
  );
});

Deno.test("duplicate observations are idempotent, conflicting duplicates fail", () => {
  const row = { data: "23/09/2026", valor: "0,055" };
  const window = { from: "2026-09-01", through: "2026-09-24" };
  assert(
    parseSgsPage(12, [row, row], "2026-09-24T10:00:00Z", window)
      .length === 1,
    "identical duplicate survived",
  );
  raises(
    "invalid_sgs_payload",
    () =>
      parseSgsPage(
        12,
        [row, { ...row, valor: "0,056" }],
        "2026-09-24T10:00:00Z",
        window,
      ),
  );
});

Deno.test("SGS requests are bounded and contain only public code/dates", () => {
  const window = collectionWindow("2016-01-01", "2026-09-24");
  assert(
    window.from === "2016-01-01" &&
      window.through === "2016-12-31" && window.nextFrom === "2017-01-01",
    "checkpoint window is not one bounded year",
  );
  const url = new URL(sgsUrl(11, window));
  assert(
    url.host === "api.bcb.gov.br" &&
      url.searchParams.get("dataInicial") === "01/01/2016" &&
      url.searchParams.get("dataFinal") === "31/12/2016" &&
      [...url.searchParams.keys()].sort().join(",") ===
        "dataFinal,dataInicial,formato",
    "SGS URL leaked private data",
  );
  raises(
    "invalid_sgs_window",
    () => sgsUrl(11, { from: "2010-01-01", through: "2020-01-01" }),
  );
  const revision = collectionWindow("2026-09-25", "2026-09-24");
  assert(
    revision.from === "2026-08-15" &&
      revision.through === "2026-09-24",
    "late publication not revisited",
  );
});

Deno.test("first collection seeds recent data without skipping historical backfill", async () => {
  const window = recentWindow("2026-09-24");
  assert(
    window.from === "2025-09-24" && window.through === "2026-09-24",
    "recent seed is outside bounded annual window",
  );
  let fetchedFrom = "";
  let completedNext = "";
  let seeded = false;
  const result = await collectSeries(
    188,
    {
      next_from: "1979-04-01",
      last_reference_start: null,
      last_reference_end: null,
      lease_token: "lease",
    },
    "2026-09-24",
    {
      fetchPage: (_code, requested) => {
        fetchedFrom = requested.from;
        return Promise.resolve([]);
      },
      upsert: () => Promise.resolve(),
      complete: (_code, _token, next, _start, _end, _count, seedRecent) => {
        completedNext = next;
        seeded = seedRecent;
        return Promise.resolve();
      },
      fail: () => Promise.reject(new Error("unexpected failure")),
    },
    true,
  );
  assert(
    result.status === "completed" && fetchedFrom === "2025-09-24" &&
      completedNext === "1979-04-01" && seeded,
    "warm-up consumed historical checkpoint",
  );
});

Deno.test("recent observations refresh on the next day during historical backfill", () => {
  assert(shouldSeedRecent(null, "2026-09-24"), "initial seed omitted");
  assert(
    !shouldSeedRecent("2026-09-24T10:00:00.000Z", "2026-09-24"),
    "same-day run repeated recent seed",
  );
  assert(
    shouldSeedRecent("2026-09-24T10:00:00.000Z", "2026-09-25"),
    "next day did not refresh recent observations",
  );
});

Deno.test("read request rejects private IDs and excessive/future range", () => {
  const valid = {
    operation: "read",
    code: 226,
    from: "2025-09-24",
    through: "2026-09-24",
  };
  assert(
    parseReadRequest(valid, "2026-09-24") !== null,
    "valid annual request rejected",
  );
  assert(
    parseReadRequest({ ...valid, vault_id: "private" }, "2026-09-24") ===
      null,
    "private ID accepted",
  );
  assert(
    parseReadRequest({ ...valid, from: "2020-01-01" }, "2026-09-24") ===
      null,
    "unbounded request accepted",
  );
  assert(
    parseReadRequest({ ...valid, through: "2026-09-25" }, "2026-09-24") ===
      null,
    "future publication accepted",
  );
});

Deno.test("empty provider window advances checkpoint without inventing zero", async () => {
  let upsertedCount = -1;
  let nextFrom = "";
  let latest: string | null = "2026-09-22";
  const ports: CollectorPorts = {
    fetchPage: () => Promise.resolve([]),
    upsert: (rows) => {
      upsertedCount = rows.length;
      return Promise.resolve();
    },
    complete: (_code, _token, next, _start, end) => {
      nextFrom = next;
      latest = end;
      return Promise.resolve();
    },
    fail: () => Promise.reject(new Error("unexpected failure")),
  };
  const result = await collectSeries(
    12,
    {
      next_from: "2026-09-23",
      last_reference_start: "2026-09-22",
      last_reference_end: "2026-09-22",
      lease_token: "lease",
    },
    "2026-09-24",
    ports,
  );
  assert(
    result.status === "completed" && result.count === 0 &&
      upsertedCount === 0 && nextFrom === "2026-09-25" &&
      latest === "2026-09-22",
    "absence was promoted to a value",
  );
});

Deno.test("provider failure records error and keeps checkpoint", async () => {
  let completed = false;
  let failed = "";
  const result = await collectSeries(
    433,
    {
      next_from: "2026-09-01",
      last_reference_start: "2026-08-01",
      last_reference_end: "2026-08-31",
      lease_token: "lease",
    },
    "2026-09-24",
    {
      fetchPage: () =>
        Promise.reject(new EconomicSeriesError("sgs_unavailable")),
      upsert: () => Promise.reject(new Error("unexpected upsert")),
      complete: () => {
        completed = true;
        return Promise.resolve();
      },
      fail: (_code, _token, error) => {
        failed = error;
        return Promise.resolve();
      },
    },
  );
  assert(
    result.status === "failed" && failed === "sgs_unavailable" &&
      !completed,
    "failure advanced checkpoint",
  );
});

Deno.test("upstream HTTP error and malformed payload are explicit", async () => {
  const window = { from: "2026-09-01", through: "2026-09-24" };
  const unpublished = await fetchSgsPage(
    12,
    window,
    () => Promise.resolve(new Response("", { status: 404 })),
  );
  assert(unpublished.length === 0, "SGS empty 404 became a rate");
  try {
    await fetchSgsPage(
      12,
      window,
      () => Promise.resolve(new Response("", { status: 503 })),
    );
    throw new Error("expected 503");
  } catch (error) {
    assert(
      error instanceof EconomicSeriesError &&
        error.code === "sgs_unavailable",
      "HTTP failure not classified",
    );
  }
  try {
    await fetchSgsPage(
      12,
      window,
      () => Promise.resolve(new Response("not-json", { status: 200 })),
    );
    throw new Error("expected parse error");
  } catch (error) {
    assert(
      error instanceof EconomicSeriesError &&
        error.code === "invalid_sgs_payload",
      "malformed JSON not rejected",
    );
  }
});
