// Read only: report processing and tester availability, without logging credentials or testers.
import { createPrivateKey, sign } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';

const buildNumber = process.env.NN_STATUS_BUILD;
const checkICloud = process.env.NN_STATUS_ICLOUD === 'true';
if (!checkICloud && !/^\d{1,10}$/.test(buildNumber ?? '')) throw new Error('A numeric build number is required');
for (const key of ['NN_ASC_KEY_BASE64', 'NN_ASC_KEY_ID', 'NN_ASC_ISSUER_ID']) {
  if (!process.env[key]) throw new Error(`Missing ${key}`);
}
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = encode({ alg: 'ES256', kid: process.env.NN_ASC_KEY_ID, typ: 'JWT' });
const payload = encode({ iss: process.env.NN_ASC_ISSUER_ID, iat: now - 30, exp: now + 600, aud: 'appstoreconnect-v1' });
const input = `${header}.${payload}`;
const key = createPrivateKey(Buffer.from(process.env.NN_ASC_KEY_BASE64, 'base64'));
const signature = sign('sha256', Buffer.from(input), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
const token = `${input}.${signature}`;
async function get(path, params = {}) {
  const url = new URL(`https://api.appstoreconnect.apple.com/v1/${path}`);
  url.search = new URLSearchParams(params).toString();
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(30000) });
  const body = await response.json();
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status}: ${JSON.stringify(body.errors?.map(e => ({ code: e.code, detail: e.detail })))}`);
  return body;
}
if (checkICloud) {
  const bundleID = 'com.lorenzominichilli.neuralnotes';
  const identifiers = await get('bundleIds', { 'filter[identifier]': bundleID });
  if (identifiers.data.length !== 1) throw new Error('Expected exactly one NeuralNotes bundle ID');
  const capabilities = await get(`bundleIds/${identifiers.data[0].id}/bundleIdCapabilities`);
  const relevant = capabilities.data.map(capability => capability.attributes).filter(attributes =>
    ['ICLOUD', 'SIGN_IN_WITH_APPLE', 'APPLE_ID_AUTH'].includes(attributes.capabilityType));
  const report = { checkedAt: new Date().toISOString(), bundleID, capabilities: relevant };
  mkdirSync('.verification', { recursive: true });
  writeFileSync('.verification/testflight-status.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
} else {
  const apps = await get('apps', { 'filter[bundleId]': 'com.lorenzominichilli.neuralnotes' });
  if (apps.data.length !== 1) throw new Error('Expected exactly one NeuralNotes app');
  const app = apps.data[0];
  const builds = await get('builds', { 'filter[app]': app.id, 'filter[version]': buildNumber, include: 'preReleaseVersion,buildBetaDetail', limit: '200' });
  const groups = await get('betaGroups', { 'filter[app]': app.id, limit: '200' });
  const report = { checkedAt: new Date().toISOString(), app: { id: app.id, name: app.attributes.name, bundleId: app.attributes.bundleId }, buildNumber, builds: [], groups: [] };
  for (const build of builds.data) {
    const related = name => builds.included?.find(v => v.id === build.relationships[name]?.data?.id && v.type === build.relationships[name]?.data?.type)?.attributes;
    report.builds.push({ id: build.id, ...build.attributes, preReleaseVersion: related('preReleaseVersion'), betaDetail: related('buildBetaDetail') });
  }
  for (const group of groups.data) {
    const linked = await get(`betaGroups/${group.id}/builds`, { limit: '200' });
    report.groups.push({ id: group.id, name: group.attributes.name, isInternalGroup: group.attributes.isInternalGroup, hasAccessToAllBuilds: group.attributes.hasAccessToAllBuilds, matchingBuildIDs: linked.data.filter(b => b.attributes.version === buildNumber).map(b => b.id), moreBuilds: Boolean(linked.links?.next) });
  }
  mkdirSync('.verification', { recursive: true });
  writeFileSync('.verification/testflight-status.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}
