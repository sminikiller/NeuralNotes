import test from 'node:test';
import assert from 'node:assert/strict';
import { configurationChecks } from './preflight.mjs';
test('preflight names missing configuration without returning secrets', () => {
  assert.deepEqual(configurationChecks({}).missing, ['NN_SUPABASE_URL','NN_SUPABASE_PUBLIC_KEY','NN_PROVIDER_KEY']);
  const report = configurationChecks({ NN_PROVIDER_KEY: 'fixture-private-do-not-log' });
  assert.ok(!JSON.stringify(report).includes('fixture-private-do-not-log'));
});
test('preflight accepts hosted public configuration and rejects service secrets', () => {
  const env = { NN_SUPABASE_URL: 'https://auth.example', NN_SUPABASE_PUBLIC_KEY: 'sb_publishable_fixture_public_only', NN_PROVIDER_KEY: 'fixture-only-key' };
  assert.equal(configurationChecks(env).configured, true);
  assert.equal(configurationChecks({ ...env, NN_SUPABASE_URL: 'http://auth.example' }).configured, false);
  assert.equal(configurationChecks({ ...env, NN_SUPABASE_PUBLIC_KEY: 'sb_secret_not_public' }).configured, false);
});
