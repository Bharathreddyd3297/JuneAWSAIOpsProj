// JWT helpers. auth-service signs tokens; every other service verifies them
// locally with the shared secret (no network hop per request).
const jwt = require('jsonwebtoken');

const SECRET = process.env.JWT_SECRET || 'dev-only-change-me';
const ISSUER = 'telugu-pickles-auth';
const TTL = process.env.JWT_TTL || '12h';

if (!process.env.JWT_SECRET && process.env.NODE_ENV === 'production') {
  // Fail fast rather than run production with a default secret.
  throw new Error('JWT_SECRET must be set in production');
}

function signToken(user) {
  return jwt.sign({ sub: user.id, email: user.email, name: user.name }, SECRET, {
    issuer: ISSUER,
    expiresIn: TTL,
  });
}

function verifyToken(token) {
  return jwt.verify(token, SECRET, { issuer: ISSUER });
}

// Express middleware: requires "Authorization: Bearer <jwt>"
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Login required' });
  }
  try {
    const claims = verifyToken(token);
    req.user = { id: claims.sub, email: claims.email, name: claims.name };
    return next();
  } catch {
    return res.status(401).json({ error: 'Session expired, please login again' });
  }
}

module.exports = { signToken, verifyToken, requireAuth };
