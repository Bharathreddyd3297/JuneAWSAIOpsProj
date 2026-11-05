const test = require('node:test');
const assert = require('node:assert');
const { signToken, verifyToken, requireAuth } = require('../common/auth');

test('signed token round-trips claims', () => {
  const token = signToken({ id: 'u-1', email: 'a@b.in', name: 'Ravi' });
  const claims = verifyToken(token);
  assert.strictEqual(claims.sub, 'u-1');
  assert.strictEqual(claims.email, 'a@b.in');
});

test('tampered token is rejected', () => {
  const token = signToken({ id: 'u-1', email: 'a@b.in', name: 'Ravi' });
  assert.throws(() => verifyToken(token.slice(0, -2) + 'xx'));
});

test('requireAuth returns 401 without bearer token', () => {
  let status;
  const res = { status: (s) => ((status = s), { json: () => {} }) };
  requireAuth({ headers: {} }, res, () => assert.fail('next should not be called'));
  assert.strictEqual(status, 401);
});
