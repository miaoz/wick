// Wishlist emails belong in the private wick-private bucket, never the release bucket.
const KEY = "wick/ios_wishlist.json";
const ALLOWED_ORIGINS = new Set([
  "https://wick.bitfroth.com", "https://wick-ccc.pages.dev", "https://wick.pages.dev"
]);
const MAX_BODY_BYTES = 1024;
const MAX_DAILY_SUBMISSIONS = 1000;

function json(payload, status = 200, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers }
  });
}
function stats(data, recorded) {
  return { ok: true, count: data.votes + data.emails.length,
    votes: data.votes, emailCount: data.emails.length,
    ...(recorded === undefined ? {} : { recorded }) };
}
async function readData(env) {
  if (!env.WISH_BUCKET) throw new Error("Missing private bucket binding");
  const obj = await env.WISH_BUCKET.get(KEY);
  if (!obj) return { data: { votes: 0, emails: [] }, etag: null };
  const data = await obj.json();
  // Never replace unreadable or malformed stored registrations with an empty list.
  if (!data || !Array.isArray(data.emails) || !Number.isSafeInteger(data.votes) || data.votes < 0 ||
      data.emails.some(it => typeof it !== "string" && (!it || typeof it.email !== "string"))) {
    throw new Error("Invalid stored wishlist");
  }
  return { data, etag: obj.etag };
}
function cacheKey(request) {
  const url = new URL(request.url);
  url.pathname = "/api/wishlist";
  url.search = "";
  return new Request(url, { method: "GET" });
}
export async function onRequestGet(context) {
  try {
    const cache = globalThis.caches?.default;
    const key = cacheKey(context.request);
    const cached = await cache?.match(key);
    if (cached) return new Response(cached.body, cached);
    const { data } = await readData(context.env);
    const response = json(stats(data), 200, { "Cache-Control": "public, max-age=60" });
    if (cache) context.waitUntil(cache.put(key, response.clone()).catch(() => {}));
    return response;
  } catch {
    return json({ ok: false, error: "Service temporarily unavailable" }, 503);
  }
}
async function readSubmission(request) {
  if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json") {
    return { error: "JSON required", status: 415 };
  }
  if (Number(request.headers.get("content-length")) > MAX_BODY_BYTES) return { error: "Request too large", status: 413 };
  const reader = request.body?.getReader();
  if (!reader) return { error: "Invalid request", status: 400 };
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY_BYTES) {
        await reader.cancel();
        return { error: "Request too large", status: 413 };
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const body = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || Array.isArray(body) || typeof body.email !== "string") return { error: "Invalid request", status: 400 };
    const email = body.email.trim();
    if (email.length > 254 || (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) return { error: "Invalid email", status: 400 };
    return { email };
  } catch {
    return { error: "Invalid request", status: 400 };
  } finally { reader.releaseLock(); }
}
export async function onRequestPost(context) {
  const { request, env } = context;
  // Keep production writes behind the zone WAF; pages.dev/preview URLs bypass it.
  if (new URL(request.url).hostname !== "wick.bitfroth.com") return json({ ok: false, error: "Use the production website" }, 403);
  if (!ALLOWED_ORIGINS.has(request.headers.get("origin"))) return json({ ok: false, error: "Origin not allowed" }, 403);
  const submission = await readSubmission(request);
  if (submission.error) return json({ ok: false, error: submission.error }, submission.status);
  try {
    // At most three reads/writes on contention; conditional failures return null in R2.
    for (let attempt = 0; attempt < 3; attempt++) {
      const { data, etag } = await readData(env);
      const email = submission.email;
      if (email && data.emails.some(it => (typeof it === "string" ? it : it.email).toLowerCase() === email.toLowerCase())) {
        return json(stats(data, false));
      }
      const day = new Date().toISOString().slice(0, 10);
      const daily = data.submissionDay === day ? data.dailySubmissions : 0;
      if (!Number.isSafeInteger(daily) || daily < 0) throw new Error("Invalid daily counter");
      if (daily >= MAX_DAILY_SUBMISSIONS) return json({ ok: false, error: "Daily limit reached, please try tomorrow" }, 429, { "Retry-After": "3600" });
      if (email) data.emails.push({ email, createdAt: new Date().toISOString() });
      else data.votes++;
      data.updatedAt = new Date().toISOString();
      data.count = data.votes + data.emails.length;
      data.submissionDay = day;
      data.dailySubmissions = daily + 1;
      const written = await env.WISH_BUCKET.put(KEY, JSON.stringify(data), {
        httpMetadata: { contentType: "application/json", cacheControl: "no-store" },
        onlyIf: etag ? { etagMatches: etag } : new Headers({ "If-None-Match": "*" })
      });
      if (written !== null) return json(stats(data, true));
    }
    return json({ ok: false, error: "Busy, please try again" }, 503, { "Retry-After": "5" });
  } catch {
    return json({ ok: false, error: "Service temporarily unavailable" }, 503);
  }
}
export async function onRequestOptions(context) {
  const origin = context.request.headers.get("origin");
  return new Response(null, { status: 204, headers: {
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type", "Vary": "Origin",
    ...(ALLOWED_ORIGINS.has(origin) ? { "Access-Control-Allow-Origin": origin } : {})
  } });
}
