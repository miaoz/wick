import test from 'node:test';
import assert from 'node:assert/strict';
import { onRequestGet, onRequestPost } from '../functions/api/wishlist.js';
const origin = 'https://wick.bitfroth.com';
function context(body = { email: '' }, bucket, headers = {}) {
  return { request: new Request(origin + '/api/wishlist?cacheBust=1', {
    method: 'POST', headers: { origin, 'Content-Type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body)
  }), env: { WISH_BUCKET: bucket }, waitUntil() {} };
}
function bucket(initial = { emails: [], votes: 0 }) {
  let data = initial;
  let version = 1;
  const calls = { get: 0, put: 0 };
  return { calls,
    async get() { calls.get++; return data === null ? null : { etag: String(version), json: async () => structuredClone(data) }; },
    async put(key, value, options) {
      calls.put++;
      const condition = options.onlyIf;
      if (data === null ? condition.get('If-None-Match') !== '*' : condition.etagMatches !== String(version)) return null;
      data = JSON.parse(value); version++; return { etag: String(version) };
    }, get data() { return data; }
  };
}
test('invalid payloads and untrusted origins never access R2', async () => {
  const b = bucket();
  for (const value of ['{broken', {}, { email: 'bad' }, 'x'.repeat(1025), null]) {
    const response = await onRequestPost(context(value, b));
    assert.ok([400, 413].includes(response.status));
  }
  assert.equal((await onRequestPost(context({ email: '' }, b, { origin: '' }))).status, 403);
  assert.deepEqual(b.calls, { get: 0, put: 0 });
});
test('preview hosts cannot bypass the zone WAF to write production data', async () => {
  const b = bucket();
  const ctx = context({ email: '' }, b);
  ctx.request = new Request('https://wick-ccc.pages.dev/api/wishlist', { method: 'POST', headers: { origin, 'Content-Type': 'application/json' }, body: '{"email":""}' });
  assert.equal((await onRequestPost(ctx)).status, 403);
  assert.deepEqual(b.calls, { get: 0, put: 0 });
});
test('duplicate registrations do not write or reveal stored emails', async () => {
  const b = bucket({ votes: 1, emails: [{ email: 'test@example.com' }] });
  const response = await onRequestPost(context({ email: 'TEST@example.com' }, b));
  assert.deepEqual(await response.json(), { ok: true, count: 2, votes: 1, emailCount: 1, recorded: false });
  assert.equal(b.calls.put, 0);
});
test('concurrent submissions retry the failed conditional update without losing votes', async () => {
  const b = bucket();
  const responses = await Promise.all([onRequestPost(context({ email: '' }, b)), onRequestPost(context({ email: '' }, b))]);
  assert.ok(responses.every(r => r.status === 200));
  assert.equal(b.data.votes, 2);
  assert.equal(b.data.dailySubmissions, 2);
  assert.equal(b.calls.put, 3);
});
test('first registration uses a create-only condition', async () => {
  const b = bucket(null);
  assert.equal((await onRequestPost(context({ email: 'new@example.com' }, b))).status, 200);
  assert.equal(b.data.emails.length, 1);
});
test('missing binding and damaged stored data fail without overwriting', async () => {
  assert.equal((await onRequestPost(context({ email: '' }, undefined))).status, 503);
  const b = bucket({ votes: -1, emails: [] });
  assert.equal((await onRequestPost(context({ email: '' }, b))).status, 503);
  assert.equal(b.calls.put, 0);
});
test('daily write limit blocks additional writes and resets on the next UTC day', async () => {
  const b = bucket({ votes: 0, emails: [], submissionDay: new Date().toISOString().slice(0, 10), dailySubmissions: 1000 });
  assert.equal((await onRequestPost(context({ email: '' }, b))).status, 429);
  assert.equal(b.calls.put, 0);
  b.data.submissionDay = '2000-01-01';
  assert.equal((await onRequestPost(context({ email: '' }, b))).status, 200);
  assert.equal(b.data.dailySubmissions, 1);
});
test('query variations share a cached public aggregate without R2 reads', async () => {
  const previous = globalThis.caches;
  const entries = new Map();
  globalThis.caches = { default: {
    async match(key) { return entries.get(key.url)?.clone(); },
    async put(key, response) { entries.set(key.url, response); }
  } };
  try {
    const b = bucket({ votes: 1, emails: ['test@example.com'] });
    const pending = [];
    for (const query of ['?a=1', '?a=2']) {
      const response = await onRequestGet({ request: new Request(origin + '/api/wishlist' + query), env: { WISH_BUCKET: b }, waitUntil(p) { pending.push(p); } });
      assert.deepEqual(await response.json(), { ok: true, count: 2, votes: 1, emailCount: 1 });
      await Promise.all(pending);
      response.headers.set('X-Middleware', 'mutable');
    }
    assert.equal(b.calls.get, 1);
  } finally { globalThis.caches = previous; }
});
