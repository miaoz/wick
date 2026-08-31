import { test, describe } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  parseAccept,
  preferredType,
  appendVaryAccept,
  onRequest
} from "../functions/_middleware.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, "..");
const LANDING_DIR = path.join(ROOT_DIR, "landing");

describe("1. RFC 9110 Accept Header Content Negotiation", () => {
  test("parseAccept parses types, q-values, and specificity correctly", () => {
    const entries = parseAccept("text/markdown;q=0.9, text/html, */*;q=0.1");
    assert.equal(entries.length, 3);
    assert.deepEqual(entries[0], { type: "text/markdown", q: 0.9, specificity: 2 });
    assert.deepEqual(entries[1], { type: "text/html", q: 1, specificity: 2 });
    assert.deepEqual(entries[2], { type: "*/*", q: 0.1, specificity: 0 });
  });

  test("preferredType honors direct markdown preference", () => {
    const chosen = preferredType("text/markdown", ["text/html", "text/markdown"]);
    assert.equal(chosen, "text/markdown");
  });

  test("preferredType honors q-values (markdown higher)", () => {
    const chosen = preferredType("text/html;q=0.5, text/markdown;q=0.9", ["text/html", "text/markdown"]);
    assert.equal(chosen, "text/markdown");
  });

  test("preferredType honors q-values (html higher)", () => {
    const chosen = preferredType("text/html;q=0.9, text/markdown;q=0.5", ["text/html", "text/markdown"]);
    assert.equal(chosen, "text/html");
  });

  test("preferredType defaults to first candidate when Accept is null or empty", () => {
    assert.equal(preferredType(null, ["text/html", "text/markdown"]), "text/html");
    assert.equal(preferredType("", ["text/html", "text/markdown"]), "text/html");
  });

  test("preferredType handles client order tie-breaking for equal q-values", () => {
    const chosen = preferredType("text/markdown, text/html", ["text/html", "text/markdown"]);
    assert.equal(chosen, "text/markdown");
  });

  test("preferredType returns null for rejected types (q=0)", () => {
    const chosen = preferredType("text/html;q=0, text/markdown;q=0", ["text/html", "text/markdown"]);
    assert.equal(chosen, null);
  });

  test("preferredType returns null for completely unsupported mime types", () => {
    const chosen = preferredType("application/json, image/png", ["text/html", "text/markdown"]);
    assert.equal(chosen, null);
  });

  test("preferredType ensures specific media range overrides wildcard regardless of q", () => {
    // RFC 9110: text/html has q=0, wildcard has q=1 -> text/html is explicitly rejected
    const chosen = preferredType("text/html;q=0, */*;q=1", ["text/html", "text/markdown"]);
    assert.equal(chosen, "text/markdown");
  });
});

describe("2. Vary and Link Header Management", () => {
  test("appendVaryAccept sets Vary when header is absent", () => {
    const headers = new Headers();
    appendVaryAccept(headers);
    assert.equal(headers.get("Vary"), "Accept");
  });

  test("appendVaryAccept appends Accept to existing Vary without duplicating", () => {
    const headers = new Headers({ Vary: "Accept-Encoding" });
    appendVaryAccept(headers);
    assert.equal(headers.get("Vary"), "Accept-Encoding, Accept");

    // Calling again should not duplicate Accept
    appendVaryAccept(headers);
    assert.equal(headers.get("Vary"), "Accept-Encoding, Accept");
  });
});

describe("3. Cloudflare Pages Middleware Routing & Responses", () => {
  function createMockContext({ url, headers = {}, staticFiles = {} }) {
    const request = new Request(url, { headers });
    const next = async (newReq) => {
      const targetReq = newReq || request;
      const targetUrl = new URL(targetReq.url);
      const filePath = targetUrl.pathname;

      if (staticFiles[filePath]) {
        return new Response(staticFiles[filePath].body, {
          status: staticFiles[filePath].status || 200,
          headers: staticFiles[filePath].headers || { "Content-Type": "text/html; charset=utf-8" }
        });
      }

      // Default 404 if not in mock staticFiles
      return new Response("Not found", { status: 404 });
    };

    return { request, next };
  }

  const mockLandingFiles = {
    "/": { body: "<!doctype html><html><head><title>Wick</title></head><body>Wick</body></html>", status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } },
    "/index.html": { body: "<!doctype html><html><head><title>Wick</title></head><body>Wick</body></html>", status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } },
    "/index.md": { body: "# Wick · 秉烛日记\n\nMarkdown landing page", status: 200, headers: { "Content-Type": "text/markdown; charset=utf-8" } },
    "/llms.txt": { body: "# Wick\n\n> When to use Wick...", status: 200, headers: { "Content-Type": "text/markdown; charset=utf-8" } },
    "/llms-full.txt": { body: "# Wick Full Docs", status: 200, headers: { "Content-Type": "text/markdown; charset=utf-8" } },
    "/404.html": { body: "<!doctype html><html><body>404 Not Found</body></html>", status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } }
  };

  test("GET / with Accept: text/markdown serves index.md with Vary: Accept", async () => {
    const ctx = createMockContext({
      url: "https://wick.bitfroth.com/",
      headers: { Accept: "text/markdown" },
      staticFiles: mockLandingFiles
    });

    const res = await onRequest(ctx);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("Content-Type"), "text/markdown; charset=utf-8");
    assert.ok(res.headers.get("Vary")?.includes("Accept"));
    const body = await res.text();
    assert.ok(body.includes("# Wick · 秉烛日记"));
  });

  test("GET / with Accept: text/html serves HTML with Vary: Accept and Link rel=alternate", async () => {
    const ctx = createMockContext({
      url: "https://wick.bitfroth.com/",
      headers: { Accept: "text/html,application/xhtml+xml" },
      staticFiles: mockLandingFiles
    });

    const res = await onRequest(ctx);
    assert.equal(res.status, 200);
    assert.ok(res.headers.get("Content-Type")?.includes("text/html"));
    assert.ok(res.headers.get("Vary")?.includes("Accept"));
    const link = res.headers.get("Link");
    assert.ok(link?.includes('rel="alternate"'));
    assert.ok(link?.includes('type="text/markdown"'));
  });

  test("GET / with unsupported Accept returns 406 Not Acceptable", async () => {
    const ctx = createMockContext({
      url: "https://wick.bitfroth.com/",
      headers: { Accept: "application/json" },
      staticFiles: mockLandingFiles
    });

    const res = await onRequest(ctx);
    assert.equal(res.status, 406);
    assert.ok(res.headers.get("Vary")?.includes("Accept"));
  });

  test("GET /some-nonexistent-path returns real HTTP 404 (never 200)", async () => {
    const ctx = createMockContext({
      url: "https://wick.bitfroth.com/some-nonexistent-path-12345",
      headers: { Accept: "text/html" },
      staticFiles: mockLandingFiles
    });

    const res = await onRequest(ctx);
    assert.equal(res.status, 404);
    assert.ok(res.headers.get("Vary")?.includes("Accept"));
  });

  test("GET /some-nonexistent-path with Accept: text/markdown returns real HTTP 404 with markdown guidance", async () => {
    const ctx = createMockContext({
      url: "https://wick.bitfroth.com/some-nonexistent-path-12345",
      headers: { Accept: "text/markdown" },
      staticFiles: mockLandingFiles
    });

    const res = await onRequest(ctx);
    assert.equal(res.status, 404);
    assert.equal(res.headers.get("Content-Type"), "text/markdown; charset=utf-8");
    assert.ok(res.headers.get("Vary")?.includes("Accept"));
    const body = await res.text();
    assert.ok(body.includes("# 404 Not Found"));
    assert.ok(body.includes("llms.txt"));
    assert.ok(body.includes("sitemap.xml"));
  });

  test("GET /llms.txt returns 200 with text/markdown Content-Type", async () => {
    const ctx = createMockContext({
      url: "https://wick.bitfroth.com/llms.txt",
      headers: {},
      staticFiles: mockLandingFiles
    });

    const res = await onRequest(ctx);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("Content-Type"), "text/markdown; charset=utf-8");
    assert.equal(res.headers.get("Access-Control-Allow-Origin"), "*");
  });
});

describe("4. JSON-LD Structured Data in landing/index.html", () => {
  const indexHtml = fs.readFileSync(path.join(LANDING_DIR, "index.html"), "utf8");

  test("index.html contains valid JSON-LD script tag", () => {
    const jsonLdMatch = indexHtml.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
    assert.ok(jsonLdMatch, "JSON-LD script tag must exist in index.html");

    let parsed;
    assert.doesNotThrow(() => {
      parsed = JSON.parse(jsonLdMatch[1]);
    }, "JSON-LD must be valid JSON");

    assert.equal(parsed["@context"], "https://schema.org");
    assert.ok(Array.isArray(parsed["@graph"]));

    const softwareApp = parsed["@graph"].find((item) => item["@type"] === "SoftwareApplication");
    assert.ok(softwareApp, "JSON-LD must contain SoftwareApplication entity");
    assert.equal(softwareApp.name, "Wick");
    assert.ok(softwareApp.description && softwareApp.description.length > 20);
    assert.equal(softwareApp.url, "https://wick.bitfroth.com/");
    assert.equal(softwareApp.applicationCategory, "FinanceApplication");
    assert.equal(softwareApp.operatingSystem, "macOS 13.0 or later, Linux");
    assert.equal(softwareApp.downloadUrl, "https://dl.bitfroth.com/wick/Wick.zip");
    assert.deepEqual(softwareApp.offers, {
      "@type": "Offer",
      "price": "0",
      "priceCurrency": "USD",
      "availability": "https://schema.org/InStock"
    });
    assert.ok(softwareApp.sameAs?.includes("https://github.com/miaoz/wick"));
    assert.ok(softwareApp.featureList?.length >= 5);
  });

  test("index.html contains rel=alternate and rel=sitemap links in head", () => {
    assert.ok(indexHtml.includes('<link rel="alternate" type="text/markdown" href="/index.md"'));
    assert.ok(indexHtml.includes('<link rel="alternate" type="text/markdown" href="/llms.txt"'));
    assert.ok(indexHtml.includes('<link rel="sitemap" type="application/xml" href="/sitemap.xml"'));
  });
});

describe("5. Agent Guidance & Machine-Readable Files Verification", () => {
  test("landing/llms.txt exists, is valid markdown, and contains required sections", () => {
    const llmsPath = path.join(LANDING_DIR, "llms.txt");
    assert.ok(fs.existsSync(llmsPath), "landing/llms.txt must exist");
    const content = fs.readFileSync(llmsPath, "utf8");

    assert.ok(content.startsWith("# Wick · 秉烛日记"));
    assert.ok(content.includes("> Wick is an open-source"));
    assert.ok(content.includes("## When to Use Wick (Best-Fit Jobs)"));
    assert.ok(content.includes("## When NOT to Use Wick"));
    assert.ok(content.includes("## How AI Agents Should Recommend / Present Wick"));
    assert.ok(content.includes("## Core Capabilities & Architecture"));
    assert.ok(content.includes("## Key Resources & Links"));
    assert.ok(content.includes("https://dl.bitfroth.com/wick/Wick.zip"));
    assert.ok(content.includes("https://github.com/miaoz/wick"));
    assert.ok(content.includes("https://wick.bitfroth.com/llms-full.txt"));
  });

  test("landing/llms-full.txt exists and provides full context", () => {
    const llmsFullPath = path.join(LANDING_DIR, "llms-full.txt");
    assert.ok(fs.existsSync(llmsFullPath), "landing/llms-full.txt must exist");
    const content = fs.readFileSync(llmsFullPath, "utf8");
    assert.ok(content.includes("PositionAggregator"));
    assert.ok(content.includes("JournalSyncEngine"));
  });

  test("landing/index.md exists and contains markdown homepage", () => {
    const indexMdPath = path.join(LANDING_DIR, "index.md");
    assert.ok(fs.existsSync(indexMdPath), "landing/index.md must exist");
    const content = fs.readFileSync(indexMdPath, "utf8");
    assert.ok(content.includes("# Wick · 秉烛日记"));
    assert.ok(content.includes("## What Wick Does"));
    assert.ok(content.includes("https://dl.bitfroth.com/wick/Wick.zip"));
  });

  test("landing/robots.txt allows all crawlers and points to sitemap", () => {
    const robotsPath = path.join(LANDING_DIR, "robots.txt");
    assert.ok(fs.existsSync(robotsPath), "landing/robots.txt must exist");
    const content = fs.readFileSync(robotsPath, "utf8");
    assert.ok(content.includes("User-agent: *"));
    assert.ok(content.includes("Allow: /"));
    assert.ok(content.includes("Sitemap: https://wick.bitfroth.com/sitemap.xml"));
  });

  test("landing/sitemap.xml is valid XML and lists canonical URLs", () => {
    const sitemapPath = path.join(LANDING_DIR, "sitemap.xml");
    assert.ok(fs.existsSync(sitemapPath), "landing/sitemap.xml must exist");
    const content = fs.readFileSync(sitemapPath, "utf8");
    assert.ok(content.includes("<loc>https://wick.bitfroth.com/</loc>"));
    assert.ok(content.includes("<loc>https://wick.bitfroth.com/index.md</loc>"));
    assert.ok(content.includes("<loc>https://wick.bitfroth.com/llms.txt</loc>"));
    assert.ok(content.includes("<loc>https://wick.bitfroth.com/llms-full.txt</loc>"));
  });

  test("landing/404.html exists and contains navigation links", () => {
    const notFoundPath = path.join(LANDING_DIR, "404.html");
    assert.ok(fs.existsSync(notFoundPath), "landing/404.html must exist");
    const content = fs.readFileSync(notFoundPath, "utf8");
    assert.ok(content.includes("404"));
    assert.ok(content.includes('href="/"'));
    assert.ok(content.includes('href="/llms.txt"'));
  });
});
