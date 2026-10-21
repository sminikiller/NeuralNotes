import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { issueToken, verifyToken, validateRequest, artifactFromResult, validateLookupRequest, lookupFromResult, validateQuizRequest, quizFromResult, ResponsesAdapter, createApp, UsageLimiter } from './server.mjs';
import { partialText } from './streaming.mjs';

function quizRequest() { return { count: 4, sources: request().sources }; }
function quizResult() { return { title: 'Ripasso', questions: [{ prompt: 'Domanda [1]', options: ['Uno', 'Due', 'Tre', 'Quattro'], correctIndex: 1, explanation: 'Spiegazione [1]', citations: [1] }] }; }

test('quiz validates source bounds and never accepts invented references or ambiguous answer indexes', () => {
  assert.equal(validateQuizRequest(quizRequest()).count, 4);
  for (const count of [0, 13, 1.5, '4']) assert.throws(() => validateQuizRequest({ ...quizRequest(), count }));
  const value = quizFromResult(quizResult(), quizRequest(), 'fixture');
  assert.deepEqual(value.questions[0].references, request().sources.map(s => s.reference));
  for (const mutation of [{ correctIndex: 4 }, { correctIndex: -1 }, { options: ['A', ' a ', 'C', 'D'] }, { options: ['A', 'B', 'C'] }, { explanation: 'Inventato [2]' }, { citations: [99] }]) {
    assert.throws(() => quizFromResult({ ...quizResult(), questions: [{ ...quizResult().questions[0], ...mutation }] }, quizRequest(), 'fixture'));
  }
  assert.throws(() => quizFromResult({ title: 'Vuoto', questions: [] }, quizRequest(), 'fixture'));
});

test('quiz adapter requires a completed strict structured response without provider identity fields', async () => {
  const adapter = new ResponsesAdapter({ key: 'test-only', model: 'fixture-model' }, async (_url, options) => {
    const body = JSON.parse(options.body); assert.equal(body.store, false); assert.equal(options.redirect, 'error');
    assert.equal(body.text.format.name, 'neuralnotes_quiz'); assert.equal(body.text.format.strict, true);
    assert.equal(JSON.parse(body.input[0].content).count, 4);
    return Response.json({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(quizResult()) }] }] });
  });
  const value = await adapter.quiz(quizRequest(), new AbortController().signal);
  assert.equal(value.questions[0].correctIndex, 1); assert.match(value.id, /^[0-9a-f-]{36}$/);
  for (const data of [{ status: 'incomplete', output: [] }, { status: 'completed', output: [{ type: 'message', content: [{ type: 'refusal' }] }] }]) {
    const refused = new ResponsesAdapter({ key: 'test-only', model: 'fixture-model' }, async () => Response.json(data));
    await assert.rejects(refused.quiz(quizRequest(), new AbortController().signal));
  }
});

test('quiz HTTP shares authorization and quotas and does not invoke the provider for invalid input', async () => {
  let calls = 0;
  const server = createApp({ secret, adapter: { async quiz(input) { calls++; return quizFromResult(quizResult(), input, 'fixture'); } }, limiter: new UsageLimiter({ perMinute: 3 }) });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}/v1/quiz`;
  try {
    const headers = { 'Content-Type': 'application/json' };
    let response = await fetch(url, { method: 'POST', headers, body: JSON.stringify(quizRequest()) }); assert.equal(response.status, 401); await response.body.cancel();
    headers.Authorization = `Bearer ${issueToken(secret, 'quiz-tester', Math.floor(Date.now() / 1000) + 60)}`;
    response = await fetch(url, { method: 'POST', headers, body: JSON.stringify({ ...quizRequest(), count: 99 }) }); assert.equal(response.status, 400); await response.body.cancel(); assert.equal(calls, 0);
    response = await fetch(url, { method: 'POST', headers, body: JSON.stringify(quizRequest()) }); assert.equal(response.status, 200); assert.equal((await response.json()).questions.length, 1); assert.equal(calls, 1);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

function lookupRequest() { return { term: 'Entropia', sources: request().sources }; }
function lookupResult() { return { term: 'Entropia', definition: 'Definizione dalle fonti [1]', explanation: 'Spiegazione [1]', examples: ['Esempio [1]'], relatedTerms: ['Calore'], citations: [1] }; }

test('lookup validates term and sources without accepting generated identities', () => {
  assert.equal(validateLookupRequest(lookupRequest()).term, 'Entropia');
  for (const term of ['', 'x'.repeat(121), 'A\nB', 4]) assert.throws(() => validateLookupRequest({ ...lookupRequest(), term }), { code: 'invalid_lookup' });
  assert.throws(() => validateLookupRequest({ ...lookupRequest(), sources: [] }), { code: 'invalid_request' });
  const result = lookupFromResult(lookupResult(), lookupRequest(), 'fixture');
  assert.deepEqual(result.references, request().sources.map(s => s.reference));
  assert.equal(result.term, 'Entropia'); assert.deepEqual(result.examples, ['Esempio [1]']);
});

test('lookup rejects wrong terms, unsupported field citations and excessive lists', () => {
  for (const mutation of [{ term: 'Altro' }, { definition: '' }, { examples: Array(6).fill('x') }, { explanation: 'Inventato [9]' }, { citations: [2] }]) {
    assert.throws(() => lookupFromResult({ ...lookupResult(), ...mutation }, lookupRequest(), 'fixture'));
  }
});

test('lookup adapter uses a strict card schema and a completed provider response', async () => {
  const adapter = new ResponsesAdapter({ key: 'test-only', model: 'fixture-model' }, async (_url, options) => {
    const body = JSON.parse(options.body); assert.equal(body.store, false);
    assert.equal(body.text.format.name, 'neuralnotes_lookup'); assert.equal(body.text.format.strict, true);
    assert.deepEqual(body.text.format.schema.required, ['term', 'definition', 'explanation', 'examples', 'relatedTerms', 'citations']);
    assert.equal(JSON.parse(body.input[0].content).term, 'Entropia');
    return Response.json({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(lookupResult()) }] }] });
  });
  const card = await adapter.lookup(lookupRequest(), new AbortController().signal);
  assert.equal(card.definition, 'Definizione dalle fonti [1]'); assert.equal(card.provider, 'OpenAI / fixture-model');
});

test('lookup HTTP shares authentication and limits and returns a structured card', async () => {
  let calls = 0;
  const adapter = { async lookup(input) { calls++; return lookupFromResult(lookupResult(), input, 'fixture'); } };
  const server = createApp({ secret, adapter, limiter: new UsageLimiter({ perMinute: 1 }) });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}/v1/lookup`;
  try {
    const options = { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(lookupRequest()) };
    let response = await fetch(url, options); assert.equal(response.status, 401); await response.body.cancel(); assert.equal(calls, 0);
    options.headers.Authorization = `Bearer ${issueToken(secret, 'lookup-tester', Math.floor(Date.now() / 1000) + 60)}`;
    response = await fetch(url, options); assert.equal(response.status, 200); assert.equal((await response.json()).term, 'Entropia');
    response = await fetch(url, options); assert.equal(response.status, 429); await response.body.cancel(); assert.equal(calls, 1);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('streamed JSON text waits for complete escapes and Unicode pairs', () => {
  const value = 'Una riga\ncon "citazione", caffè e 😀';
  const raw = '{"text":' + JSON.stringify(value) + ',"citations":[1]}';
  let previous = '';
  for (let i = 0; i <= raw.length; i++) {
    const partial = partialText(raw.slice(0, i)); assert.ok(partial.startsWith(previous)); previous = partial;
  }
  assert.equal(previous, value);
  assert.equal(partialText('{"text":"\\uD83D'), '');
  assert.equal(partialText('{"text":"\\uD83D\\uDE00'), '😀');
});

function streamFixture(citations = [1], complete = true) {
  const text = 'Risposta italiana [1].', output = JSON.stringify({ text, citations });
  const frames = [...Array.from(output).map(delta => ({ type: 'response.output_text.delta', delta }))];
  if (complete) frames.push({ type: 'response.completed', response: { status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: output }] }] } });
  const bytes = new TextEncoder().encode(frames.map(event => 'data: ' + JSON.stringify(event) + '\r\n\r\n').join(''));
  return new Response(new ReadableStream({ start(controller) { for (let i = 0; i < bytes.length; i += 7) controller.enqueue(bytes.slice(i, i + 7)); controller.close(); } }));
}
test('real streaming adapter emits deltas and only then a validated artifact', async () => {
  const adapter = new ResponsesAdapter({ key: 'test-only', model: 'fixture-model' }, async (_url, call) => {
    assert.equal(JSON.parse(call.body).stream, true); assert.equal(call.redirect, 'error'); return streamFixture();
  });
  const events = []; for await (const event of adapter.generateStream(request(), new AbortController().signal)) events.push(event);
  assert.equal(events.filter(e => e.type === 'delta').map(e => e.text).join(''), 'Risposta italiana [1].');
  assert.equal(events.at(-1).type, 'result'); assert.deepEqual(events.at(-1).artifact.references, request().sources.map(s => s.reference));
});
test('truncated streams and invented citations never emit a completed artifact', async () => {
  for (const [citations, complete] of [[[1], false], [[99], true]]) {
    const adapter = new ResponsesAdapter({ key: 'test-only', model: 'fixture-model' }, async () => streamFixture(citations, complete));
    const events = [];
    await assert.rejects(async () => { for await (const event of adapter.generateStream(request(), new AbortController().signal)) events.push(event); });
    assert.ok(events.every(e => e.type !== 'result'));
  }
});

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

test('HTTP streaming authenticates first and delivers deltas before the validated result', async () => {
  let calls = 0;
  const adapter = { async *generateStream(input) {
    calls++; yield { type: 'delta', text: 'Risposta [1]' };
    yield { type: 'result', artifact: artifactFromResult({ text: 'Risposta [1]', citations: [1] }, input, 'test-only') };
  } };
  const server = createApp({ secret, adapter }); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}/v1/study`;
  const headers = { 'Content-Type': 'application/json', Accept: 'application/x-ndjson' };
  try {
    const denied = await fetch(url, { method: 'POST', headers, body: JSON.stringify(request()) });
    assert.equal(denied.status, 401); await denied.body.cancel(); assert.equal(calls, 0);
    headers.Authorization = `Bearer ${issueToken(secret, 'stream-tester', Math.floor(Date.now() / 1000) + 60)}`;
    const response = await fetch(url, { method: 'POST', headers, body: JSON.stringify(request()) });
    assert.equal(response.status, 200); assert.match(response.headers.get('content-type'), /^application\/x-ndjson/);
    const events = (await response.text()).trim().split('\n').map(line => JSON.parse(line));
    assert.deepEqual(events.map(event => event.type), ['delta', 'result']);
    assert.deepEqual(events[1].artifact.references, request().sources.map(source => source.reference));
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('disconnecting a streaming client aborts upstream work', { timeout: 5000 }, async () => {
  let confirmAbort;
  const aborted = new Promise(resolve => { confirmAbort = resolve; });
  const adapter = { async *generateStream(_input, signal) {
    yield { type: 'delta', text: 'Inizio' };
    await new Promise(resolve => {
      const stop = () => { confirmAbort(); resolve(); };
      if (signal.aborted) stop(); else signal.addEventListener('abort', stop, { once: true });
    });
  } };
  const server = createApp({ secret, adapter }); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const cancelled = new AbortController();
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/study`, {
      method: 'POST', signal: cancelled.signal,
      headers: { 'Content-Type': 'application/json', Accept: 'application/x-ndjson', Authorization: `Bearer ${issueToken(secret, 'cancel-tester', Math.floor(Date.now() / 1000) + 60)}` },
      body: JSON.stringify(request())
    });
    const first = await response.body.getReader().read(); assert.equal(first.done, false);
    cancelled.abort(); await aborted;
  } finally { cancelled.abort(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
