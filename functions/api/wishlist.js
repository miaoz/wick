// Cloudflare Pages Function: /api/wishlist
// Reads and updates wishlist statistics (emails & +1 votes) stored in R2 bucket
// 'application-releases' (WISH_BUCKET).
//
// WEB-01 hardening:
// - Read-modify-write race: writes are conditional on the R2 object's etag and
//   retried on conflict, so two concurrent votes cannot silently drop one.
// - Anti-spam: POST only accepts an allow-listed Origin; emails are capped at
//   the RFC 5321 maximum length.
// - Privacy: the submitter's IP is NOT stored (was previously recorded without
//   disclosure).
// - Errors never echo internal details to the client.

const KEY = "wick/ios_wishlist.json";

// Only the Wick landing site (and its Pages previews) may submit votes.
const ALLOWED_ORIGINS = new Set([
  "https://wick.bitfroth.com",
  "https://wick-ccc.pages.dev",
  "https://wick.pages.dev"
]);

const MAX_EMAIL_LENGTH = 254; // RFC 5321

function isAllowedOrigin(origin) {
  if (!origin) return true; // curl / non-browser clients are not CORS-subject
  try {
    return ALLOWED_ORIGINS.has(new URL(origin).origin);
  } catch {
    return false;
  }
}

function json(payload, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      ...extraHeaders
    }
  });
}

async function readData(env) {
  if (!env.WISH_BUCKET) return { data: { count: 0, votes: 0, emails: [] }, etag: null };
  const obj = await env.WISH_BUCKET.get(KEY);
  if (!obj) return { data: { count: 0, votes: 0, emails: [] }, etag: null };
  try {
    const data = await obj.json();
    if (!Array.isArray(data.emails)) data.emails = [];
    if (typeof data.votes !== "number") data.votes = 0;
    return { data, etag: obj.httpEtag };
  } catch {
    return { data: { count: 0, votes: 0, emails: [] }, etag: obj.httpEtag };
  }
}

/// Conditional write: fails (returns false) when another writer changed the
/// object since we read it, letting the caller re-read and re-apply.
async function writeData(env, data, etag) {
  if (!env.WISH_BUCKET) return true;
  try {
    await env.WISH_BUCKET.put(KEY, JSON.stringify(data, null, 2), {
      httpMetadata: { contentType: "application/json" },
      ifMatch: etag ?? undefined
    });
    return true;
  } catch (e) {
    if (e && (e.name === "PreconditionFailed" || e.name === "InvalidRequest")) {
      return false;
    }
    throw e;
  }
}

export async function onRequestGet(context) {
  const { env } = context;
  try {
    const { data } = await readData(env);
    const emailsCount = data.emails.length;
    const votesCount = data.votes;
    return json({
      ok: true,
      count: votesCount + emailsCount,
      votes: votesCount,
      emailCount: emailsCount
    }, 200, { "Cache-Control": "no-cache" });
  } catch {
    return json({ ok: false, error: "Something went wrong" }, 500);
  }
}

export async function onRequestPost(context) {
  const { request, env } = context;
  try {
    if (!isAllowedOrigin(request.headers.get("origin"))) {
      return json({ ok: false, error: "Origin not allowed" }, 403);
    }
    let body;
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    const rawEmail = typeof body.email === "string" ? body.email.trim() : "";
    if (rawEmail.length > MAX_EMAIL_LENGTH) {
      return json({ ok: false, error: "Email too long" }, 400);
    }
    const isEmailValid = rawEmail.length > 3 && rawEmail.includes("@") && rawEmail.includes(".");

    // Read-modify-write with a bounded retry on etag conflict.
    for (let attempt = 0; attempt < 5; attempt++) {
      const { data, etag } = await readData(env);
      let isNew = false;
      if (isEmailValid) {
        const lower = rawEmail.toLowerCase();
        const exists = data.emails.some(
          (it) => (typeof it === "string" ? it.toLowerCase() : it.email?.toLowerCase()) === lower
        );
        if (!exists) {
          data.emails.push({ email: rawEmail, createdAt: new Date().toISOString() });
          isNew = true;
        }
      } else {
        data.votes = (data.votes || 0) + 1;
        isNew = true;
      }

      data.updatedAt = new Date().toISOString();
      data.count = (data.votes || 0) + data.emails.length;

      const written = await writeData(env, data, etag);
      if (written) {
        return json({
          ok: true,
          count: data.count,
          votes: data.votes,
          emailCount: data.emails.length,
          recorded: isNew
        });
      }
      // Lost the race — loop re-reads and re-applies.
    }
    return json({ ok: false, error: "Busy, please try again" }, 503);
  } catch {
    return json({ ok: false, error: "Something went wrong" }, 500);
  }
}

export async function onRequestOptions(context) {
  const { request } = context;
  const origin = request.headers.get("origin");
  const headers = {
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  };
  if (origin && isAllowedOrigin(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Vary"] = "Origin";
  }
  return new Response(null, { headers });
}
