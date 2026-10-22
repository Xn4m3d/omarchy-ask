const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../agents.js'), 'utf8').replace(/^\.pragma library\s*/, ''), context);
const adapter = context.forAgent('opencode');
const argv = opts => Array.from(adapter.argv({ prompt: 'hello', ...opts }));
const parse = obj => adapter.parse(JSON.stringify(obj));

test('OpenCode uses plan, JSONL, and the configured default model', () => {
  const args = argv();
  assert.equal(context.supportsInline('opencode'), true);
  assert.deepEqual(args.slice(4), ['opencode', 'run', '--format', 'json', '--agent', 'plan', 'hello']);
  assert.equal(args.includes('--auto'), false);
});

test('explicit model and follow-up session are separate arguments', () => {
  const args = argv({ opencodeModel: 'provider/model', sessionId: 'ses_test' });
  assert.deepEqual(args.slice(-5), ['--model', 'provider/model', '--session', 'ses_test', 'hello']);
});

test('the launch wrapper closes stdin and preserves literal prompt text', () => {
  const prompt = 'quote\' " $HOME $(printf INJECTED) `printf INJECTED`\nsecond line';
  const args = argv({ prompt });
  // Replace the actual agent with a fixture, preserving the production wrapper.
  const fixture = 'const fs=require("node:fs"); process.stdout.write(JSON.stringify({input:fs.readFileSync(0,"utf8"),prompt:process.argv[1]}));';
  const result = spawnSync(args[0], [...args.slice(1, 4), process.execPath, '-e', fixture, prompt], {
    input: 'stdin must be discarded', encoding: 'utf8', timeout: 3000,
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), { input: '', prompt });
});

test('real OpenCode event shapes produce session and text events', () => {
  const session = parse({ type: 'step_start', sessionID: 'ses_example', part: { type: 'step-start' } });
  assert.equal(session.kind, 'session');
  assert.equal(session.sessionId, 'ses_example');
  const text = parse({ type: 'text', sessionID: 'ses_example', part: { type: 'text', text: '`yy` yanks a line.' } });
  assert.equal(text.kind, 'delta');
  assert.equal(text.text, '`yy` yanks a line.');
  assert.equal(parse({ type: 'step_finish', part: { reason: 'tool-calls' } }), null);
});

test('errors surface while malformed and unknown events are ignored', () => {
  assert.equal(parse({ type: 'error', error: { type: 'provider.auth', message: 'Not signed in' } }).text, 'Not signed in');
  assert.equal(parse({ type: 'error' }).kind, 'error');
  for (const line of ['', '{broken', 'null', '[]', '42']) assert.equal(adapter.parse(line), null);
  for (const event of [{}, { type: 'new-event' }, { type: 'text' }, { type: 'text', part: { text: {} } }])
    assert.equal(parse(event), null);
});

test('existing adapters remain available', () => {
  assert.equal(context.forAgent('claude').argv({ prompt: 'hello' }).includes('hello'), true);
  assert.equal(context.forAgent('grok').parse('{broken'), null);
  assert.equal(context.forAgent('missing'), null);
});
