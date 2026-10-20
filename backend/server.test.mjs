import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { issueToken, verifyToken, validateRequest, artifactFromResult, ResponsesAdapter, createApp, UsageLimiter } from './server.mjs';

const secret = 'test-only-secret-that-is-not-a-deployment-credential';
function request() {
  return { task: 'summarize', question: '', sources: [
    { text: 'La fotosintesi converte energia luminosa in energia chimica.', reference: {
      documentID: 'FD239531-F333-4729-AB61-AE54E4BA1A11', pageID: '06BEBEC2-7615-4666-A313-C285EE1E3AF0', pageRevision: 4
    } }
  ] };
}

test('authentication rejects expired, altered and malformed tokens', () => {
  const token = issueToken(secret, 'person', 2000);
  assert.equal(verifyToken(secret, token, 1999), 'person');
  assert.equal(verifyToken(secret, token, 2000), null);
  assert.equal(verifyToken(secret, token.replace(/^./, 'A'), 1999), null);
  assert.equal(verifyToken(secret, 'bad.token', 1000), null);
  assert.equal(verifyToken(secret, token + '.extra', 1000), null);
});

test('invalid source identity and excessive context are rejected', () => {
  const input = request(); input.sources[0].reference.pageID = '../outside';
  assert.throws(() => validateRequest(input), { code: 'invalid_request' });
  const large = request(); large.sources = Array.from({ length: 41 }, () => large.sources[0]);
  assert.throws(() => validateRequest(large), { code: 'invalid_request' });
});

test('model cannot invent references or cite a source it did not select', () => {
  assert.throws(() => artifactFromResult({ text: 'Risposta [2]', citations: [2] }, request(), 'test'), { code: 'invalid_provider_citations' });
  assert.throws(() => artifactFromResult({ text: 'Risposta [2]', citations: [1] }, request(), 'test'), { code: 'invalid_provider_citations' });
  const source = request(); source.sources.push({ ...source.sources[0], reference: { documentID: source.sources[0].reference.documentID, seconds: 24, audioSessionID: 'A2121C11-53C6-4F17-B103-A5E30E0E433A' } });
  const result = artifactFromResult({ text: 'Risposta [2]', citations: [2] }, source, 'test');
  assert.equal(result.text, 'Risposta [1]'); assert.deepEqual(result.references, [source.sources[1].reference]);
});

test('limits are per user, with an independent daily ceiling', () => {
  const limiter = new UsageLimiter({ perMinute: 1, perDay: 2 });
  assert.equal(limiter.take('a', 0), true); assert.equal(limiter.take('a', 100), false);
  assert.equal(limiter.take('b', 100), true); assert.equal(limiter.take('a', 60_000), true);
  assert.equal(limiter.take('a', 120_000), false); assert.equal(limiter.take('a', 86_400_000), true);
});

test('Responses adapter parses a completed structured response and isolates source text', async () => {
  let sent;
  const transport = async (url, options) => {
    sent = JSON.parse(options.body);
    assert.equal(url, 'https://api.openai.com/v1/responses');
    assert.equal(options.redirect, 'error');
    return Response.json({ status: 'completed', output: [{ type: 'message', content: [
      { type: 'output_text', text: JSON.stringify({ text: 'Energia chimica [1]', citations: [1] }) }
    ] }] });
  };
  const adapter = new ResponsesAdapter({ key: 'test-only', model: 'configured-test-model' }, transport);
  const result = await adapter.generate(request(), new AbortController().signal);
  assert.equal(sent.store, false); assert.equal(sent.text.format.strict, true);
  assert.equal(sent.instructions.includes(request().sources[0].text), false);
  assert.deepEqual(JSON.parse(sent.input[0].content).sources, [{ id: 1, text: request().sources[0].text }]);
  assert.deepEqual(result.references, [request().sources[0].reference]);
});

test('provider refusal and incomplete output are not presented as a generated answer', async () => {
  for (const [payload, code] of [
    [{ status: 'completed', output: [{ type: 'message', content: [{ type: 'refusal', refusal: 'refused' }] }] }, 'provider_refusal'],
    [{ status: 'incomplete', output: [] }, 'provider_incomplete']
  ]) {
    const adapter = new ResponsesAdapter({ key: 'test-only', model: 'configured-test-model' }, async () => Response.json(payload));
    await assert.rejects(adapter.generate(request(), new AbortController().signal), { code });
  }
});

test('HTTP endpoint rejects unauthorized requests before invoking the provider and applies rate limits', async () => {
  let calls = 0;
  const adapter = { async generate(input) { calls++; return artifactFromResult({ text: 'Risposta [1]', citations: [1] }, input, 'test-only'); } };
  const server = createApp({ secret, adapter, limiter: new UsageLimiter({ perMinute: 1 }) });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}/v1/study`;
  try {
    let response = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(request()) });
    assert.equal(response.status, 401); await response.body.cancel(); assert.equal(calls, 0);
    const token = issueToken(secret, 'tester', Math.floor(Date.now() / 1000) + 60);
    const options = { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(request()) };
    response = await fetch(url, options); assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).references, [request().sources[0].reference]);
    response = await fetch(url, options); assert.equal(response.status, 429); await response.body.cancel();
    assert.equal(calls, 1);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
