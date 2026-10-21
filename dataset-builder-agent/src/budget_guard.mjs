// Spending guardrail for DeepClause runs.
//
// Preload it into the deepclause process:
//   NODE_OPTIONS="--import $PWD/budget_guard.mjs" BUDGET_USD=5 deepclause run ...
//
// It wraps fetch, reads the token usage out of every Anthropic API response,
// and keeps a running cost. Once the cost reaches BUDGET_USD, the next model
// call is refused and the process exits with code 3. The check happens before
// each call, so the run can overshoot by at most the cost of one call.
// Every call is appended to BUDGET_LOG (default: budget_guard.log) as a JSON
// line.

import { appendFileSync } from 'node:fs';

const BUDGET_USD = Number(process.env.BUDGET_USD ?? 5);
const LOG_FILE = process.env.BUDGET_LOG ?? 'budget_guard.log';
const API_HOST = process.env.BUDGET_GUARD_HOST ?? 'api.anthropic.com';

// USD per million tokens: [input, output]. A model that is not listed is
// charged at the most expensive rate, so the guard can only stop too early.
const PRICES = [
  ['claude-sonnet-4-6', 3, 15],
  ['claude-opus-4', 5, 25],
  ['claude-haiku-4-5', 1, 5],
];
const FALLBACK_PRICE = [10, 50];

// Cache writes cost more than plain input; cache reads are charged here at
// the full input rate, which overestimates them.
const CACHE_WRITE_MULTIPLIER = 1.25;

const totals = { calls: 0, inputTokens: 0, outputTokens: 0, costUsd: 0 };

function priceFor(model) {
  const row = PRICES.find(([prefix]) => String(model ?? '').startsWith(prefix));
  return row ? [row[1], row[2]] : FALLBACK_PRICE;
}

function usageFromBody(text) {
  // Non-streaming responses are one JSON object; streaming ones are SSE.
  const merged = { model: undefined, usage: {} };
  const absorb = (obj) => {
    const message = obj?.message ?? obj;
    if (message?.model) merged.model = message.model;
    const usage = obj?.usage ?? obj?.message?.usage;
    if (usage) Object.assign(merged.usage, usage);
  };
  try {
    absorb(JSON.parse(text));
  } catch {
    for (const line of text.split('\n')) {
      if (!line.startsWith('data:')) continue;
      try { absorb(JSON.parse(line.slice(5))); } catch { /* not JSON */ }
    }
  }
  return merged;
}

function record(text) {
  const { model, usage } = usageFromBody(text);
  const input = usage.input_tokens ?? 0;
  const cacheWrite = usage.cache_creation_input_tokens ?? 0;
  const cacheRead = usage.cache_read_input_tokens ?? 0;
  const output = usage.output_tokens ?? 0;
  const [inPrice, outPrice] = priceFor(model);
  const cost = ((input + cacheRead) * inPrice
    + cacheWrite * inPrice * CACHE_WRITE_MULTIPLIER
    + output * outPrice) / 1e6;
  totals.calls += 1;
  totals.inputTokens += input + cacheWrite + cacheRead;
  totals.outputTokens += output;
  totals.costUsd += cost;
  try {
    appendFileSync(LOG_FILE, JSON.stringify({
      call: totals.calls, model, input, cacheWrite, cacheRead, output,
      callCostUsd: Number(cost.toFixed(6)),
      totalCostUsd: Number(totals.costUsd.toFixed(6)),
    }) + '\n');
  } catch { /* logging must never break the run */ }
}

const originalFetch = globalThis.fetch;

globalThis.fetch = async function guardedFetch(input, init) {
  const url = typeof input === 'string' ? input : (input?.url ?? String(input));
  let host = '';
  try { host = new URL(url).host; } catch { /* relative or invalid URL */ }
  if (host !== API_HOST) return originalFetch(input, init);

  if (totals.costUsd >= BUDGET_USD) {
    console.error(`[budget_guard] Budget of $${BUDGET_USD} reached `
      + `($${totals.costUsd.toFixed(4)} over ${totals.calls} calls). Stopping.`);
    process.exit(3);
  }
  const response = await originalFetch(input, init);
  try {
    record(await response.clone().text());
  } catch { /* an unreadable body is not counted */ }
  return response;
};

process.on('exit', () => {
  if (totals.calls > 0) {
    console.error(`[budget_guard] ${totals.calls} model call(s), `
      + `${totals.inputTokens} input + ${totals.outputTokens} output tokens, `
      + `about $${totals.costUsd.toFixed(4)} (limit $${BUDGET_USD}).`);
  }
});
