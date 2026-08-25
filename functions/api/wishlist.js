// Cloudflare Pages Function: /api/wishlist
// Reads and updates wishlist statistics (emails & +1 votes) stored in R2 bucket 'application-releases' (WISH_BUCKET)

export async function onRequestGet(context) {
  const { env } = context;
  try {
    let data = { count: 0, votes: 0, emails: [] };
    if (env.WISH_BUCKET) {
      const obj = await env.WISH_BUCKET.get("wick/ios_wishlist.json");
      if (obj) {
        try {
          data = await obj.json();
        } catch (_) {}
      }
    }
    const emailsCount = Array.isArray(data.emails) ? data.emails.length : 0;
    const votesCount = typeof data.votes === "number" ? data.votes : 0;
    const total = votesCount + emailsCount;

    return new Response(JSON.stringify({
      ok: true,
      count: total,
      votes: votesCount,
      emailCount: emailsCount
    }), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-cache"
      }
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: e.message }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
    });
  }
}

export async function onRequestPost(context) {
  const { request, env } = context;
  try {
    const body = await request.json().catch(() => ({}));
    const rawEmail = typeof body.email === "string" ? body.email.trim() : "";
    const isEmailValid = rawEmail.length > 3 && rawEmail.includes("@") && rawEmail.includes(".");

    let data = { count: 0, votes: 0, emails: [] };
    if (env.WISH_BUCKET) {
      const obj = await env.WISH_BUCKET.get("wick/ios_wishlist.json");
      if (obj) {
        try {
          data = await obj.json();
        } catch (_) {}
      }
    }
    if (!Array.isArray(data.emails)) data.emails = [];
    if (typeof data.votes !== "number") data.votes = 0;

    let isNew = false;
    if (isEmailValid) {
      const lower = rawEmail.toLowerCase();
      const exists = data.emails.some(it => (typeof it === "string" ? it.toLowerCase() : it.email?.toLowerCase()) === lower);
      if (!exists) {
        data.emails.push({
          email: rawEmail,
          createdAt: new Date().toISOString(),
          ip: request.headers.get("cf-connecting-ip") || ""
        });
        isNew = true;
      }
    } else {
      data.votes = (data.votes || 0) + 1;
      isNew = true;
    }

    data.updatedAt = new Date().toISOString();
    data.count = (data.votes || 0) + data.emails.length;

    if (env.WISH_BUCKET) {
      await env.WISH_BUCKET.put("wick/ios_wishlist.json", JSON.stringify(data, null, 2), {
        httpMetadata: { contentType: "application/json" }
      });
    }

    return new Response(JSON.stringify({
      ok: true,
      count: data.count,
      votes: data.votes,
      emailCount: data.emails.length,
      recorded: isNew
    }), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      }
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: e.message }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
    });
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type"
    }
  });
}
