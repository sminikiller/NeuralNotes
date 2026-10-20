import { issueToken } from './server.mjs';
const secret = process.env.NN_AUTH_SECRET;
const subject = process.argv[2];
if (!secret || secret.length < 32 || !subject || subject.length > 120) {
  console.error('Set NN_AUTH_SECRET (32+ characters), then: node issue-token.mjs personal-user');
  process.exitCode = 1;
} else {
  console.log(issueToken(secret, subject, Math.floor(Date.now() / 1000) + 86400));
}
