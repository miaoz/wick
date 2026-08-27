// Cloudflare Pages Functions Middleware for Wick (functions/_middleware.js)
// Implements:
// 1. RFC 9110 Content Negotiation for Accept: text/markdown (acceptmarkdown.com compliant)
// 2. Cache headers (Vary: Accept, Link: </index.md>; rel="alternate"; type="text/markdown")
// 3. 406 Not Acceptable handling
// 4. Agent-friendly real HTTP 404s with markdown fallback

const KNOWN_STATIC_EXT = /\.(?:css|js|mjs|map|png|jpe?g|webp|gif|svg|avif|ico|woff2?|ttf|otf|eot|xml|txt|json|pdf|mp4|webm|mp3|wav|ogg|zip|md)$/i;

const NOT_FOUND_MD = `# 404 Not Found

The requested URL was not found on this server.

## Available Resources
- Homepage: https://wick.bitfroth.com/
- Agent Guidance (llms.txt): https://wick.bitfroth.com/llms.txt
- Full LLM Context (llms-full.txt): https://wick.bitfroth.com/llms-full.txt
- Markdown Homepage: https://wick.bitfroth.com/index.md
- XML Sitemap: https://wick.bitfroth.com/sitemap.xml
- GitHub Repository: https://github.com/miaoz/wick
`;

/**
 * Parse an Accept header into structured entries with q-values and specificity.
 * Complies with RFC 9110 §12.5.1
 */
export function parseAccept(header) {
  if (!header) return [];
  return header
    .split(",")
    .map((raw) => {
      const parts = raw.trim().split(";").map((s) => s.trim());
      const type = parts[0].toLowerCase();
      if (!type) return null;
      let q = 1;
      for (const param of parts.slice(1)) {
        const [name, value] = param.split("=").map((s) => s.trim());
        if (name && name.toLowerCase() === "q") {
          const parsed = Number(value);
          if (!Number.isNaN(parsed)) {
            q = Math.max(0, Math.min(1, parsed));
          }
        }
      }
      const specificity = type === "*/*" ? 0 : type.endsWith("/*") ? 1 : 2;
      return { type, q, specificity };
    })
    .filter(Boolean);
}

export function matches(entry, candidate) {
  if (entry.type === "*/*") return true;
  if (entry.type.endsWith("/*")) {
    const prefix = entry.type.slice(0, -1);
    return candidate.startsWith(prefix);
  }
  return entry.type === candidate;
}

/**
 * Select the preferred MIME type among candidates according to RFC 9110.
 * Returns null if client explicitly rejected all candidates (e.g. q=0 or unsupported mime types).
 */
export function preferredType(header, produces) {
  if (!header) return produces[0] ?? null;
  const entries = parseAccept(header);
  if (entries.length === 0) return produces[0] ?? null;

  let bestType = null;
  let bestQ = -1;
  let bestPosition = Infinity;

  for (const candidate of produces) {
    let matched = null;
    let matchedPosition = Infinity;

    for (let idx = 0; idx < entries.length; idx++) {
      const e = entries[idx];
      if (!matches(e, candidate)) continue;
      if (
        matched === null ||
        e.specificity > matched.specificity ||
        (e.specificity === matched.specificity && idx < matchedPosition)
      ) {
        matched = e;
        matchedPosition = idx;
      }
    }

    if (matched === null) continue;
    if (matched.q <= 0) continue; // explicit rejection q=0

    if (
      matched.q > bestQ ||
      (matched.q === bestQ && matchedPosition < bestPosition)
    ) {
      bestQ = matched.q;
      bestPosition = matchedPosition;
      bestType = candidate;
    }
  }

  return bestType;
}

export function appendVaryAccept(headers) {
  const existing = headers.get("Vary");
  if (!existing) {
    headers.set("Vary", "Accept");
    return;
  }
  const tokens = existing.split(",").map((s) => s.trim().toLowerCase());
  if (!tokens.includes("accept")) {
    headers.set("Vary", `${existing}, Accept`);
  }
}

export async function onRequest(context) {
  const res = await handleRequest(context);
  // Security headers (WEB-02): applied to every response. The landing page has
  // inline scripts/styles, so CSP keeps 'unsafe-inline' for those directives.
  if (!res.headers.has("X-Content-Type-Options")) {
    res.headers.set("X-Content-Type-Options", "nosniff");
  }
  if (!res.headers.has("X-Frame-Options")) {
    res.headers.set("X-Frame-Options", "DENY");
  }
  if (!res.headers.has("Referrer-Policy")) {
    res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  }
  if (!res.headers.has("Content-Security-Policy")) {
    res.headers.set(
      "Content-Security-Policy",
      [
        "default-src 'self'",
        "img-src 'self' data:",
        "style-src 'self' 'unsafe-inline'",
        "font-src 'self' data:",
        "script-src 'self' 'unsafe-inline'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'"
      ].join("; ")
    );
  }
  return res;
}

async function handleRequest(context) {
  const { request, next } = context;
  const url = new URL(request.url);

  // 1. API routes: bypass directly
  if (url.pathname.startsWith("/api/")) {
    return next();
  }

  const acceptHeader = request.headers.get("accept");

  // 2. Specific machine-readable files
  if (url.pathname === "/llms.txt" || url.pathname === "/llms-full.txt") {
    const res = await next();
    if (res.status === 200) {
      const newRes = new Response(res.body, res);
      newRes.headers.set("Content-Type", "text/markdown; charset=utf-8");
      newRes.headers.set("Access-Control-Allow-Origin", "*");
      return newRes;
    }
    return handle404(request, acceptHeader, context);
  }

  if (url.pathname === "/index.md") {
    const res = await next();
    if (res.status === 200) {
      const newRes = new Response(res.body, res);
      newRes.headers.set("Content-Type", "text/markdown; charset=utf-8");
      newRes.headers.set("Access-Control-Allow-Origin", "*");
      appendVaryAccept(newRes.headers);
      return newRes;
    }
    return handle404(request, acceptHeader, context);
  }

  // 3. Static assets with file extensions (images, fonts, stylesheets, scripts, sitemap, robots)
  if (KNOWN_STATIC_EXT.test(url.pathname)) {
    const res = await next();
    if (res.status === 404) {
      return handle404(request, acceptHeader, context);
    }
    return res;
  }

  // 4. Root landing page (/ or /index.html)
  if (url.pathname === "/" || url.pathname === "/index.html") {
    const chosen = preferredType(acceptHeader, ["text/html", "text/markdown"]);

    // Client explicitly sent Accept header but rejected all supported types (q=0 or non-matching)
    if (chosen === null && acceptHeader) {
      const notAcceptableRes = new Response(
        "Not Acceptable\n\nAvailable representations: text/html, text/markdown\n",
        {
          status: 406,
          headers: {
            "Content-Type": "text/plain; charset=utf-8",
            "Vary": "Accept",
            "Access-Control-Allow-Origin": "*"
          }
        }
      );
      return notAcceptableRes;
    }

    // Markdown preferred
    if (chosen === "text/markdown") {
      const mdReq = new Request(new URL("/index.md", url), request);
      const mdRes = await next(mdReq);
      if (mdRes.status === 200) {
        const res = new Response(mdRes.body, mdRes);
        res.headers.set("Content-Type", "text/markdown; charset=utf-8");
        res.headers.set("Access-Control-Allow-Origin", "*");
        appendVaryAccept(res.headers);
        return res;
      }
    }

    // HTML default / preferred
    const htmlRes = await next();
    const res = new Response(htmlRes.body, htmlRes);
    appendVaryAccept(res.headers);
    const linkValue = '</index.md>; rel="alternate"; type="text/markdown"';
    const existingLink = res.headers.get("Link");
    res.headers.set("Link", existingLink ? `${existingLink}, ${linkValue}` : linkValue);
    return res;
  }

  // 5. Any other path is nonexistent in this landing project -> Agent-friendly 404
  return handle404(request, acceptHeader, context);
}

async function handle404(request, acceptHeader, context) {
  const chosen = preferredType(acceptHeader, ["text/html", "text/markdown"]);

  // If client prefers markdown (or is an agent asking for markdown)
  if (chosen === "text/markdown") {
    const res = new Response(NOT_FOUND_MD, {
      status: 404,
      headers: {
        "Content-Type": "text/markdown; charset=utf-8",
        "Vary": "Accept",
        "Access-Control-Allow-Origin": "*"
      }
    });
    return res;
  }

  // HTML client / browser: fetch 404.html with real 404 status
  const notFoundReq = new Request(new URL("/404.html", request.url), request);
  const notFoundRes = await context.next(notFoundReq);
  if (notFoundRes.status === 200 || notFoundRes.status === 404) {
    const res = new Response(notFoundRes.body, {
      status: 404,
      statusText: "Not Found",
      headers: notFoundRes.headers
    });
    appendVaryAccept(res.headers);
    return res;
  }

  // Fallback if 404.html could not be fetched
  const fallbackRes = new Response(NOT_FOUND_MD, {
    status: 404,
    statusText: "Not Found",
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Vary": "Accept",
      "Access-Control-Allow-Origin": "*"
    }
  });
  return fallbackRes;
}
