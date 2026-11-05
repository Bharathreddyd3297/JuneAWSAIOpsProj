// Service-to-service HTTP client (Node's built-in fetch) with:
//   - timeout, request-id + auth header propagation
//   - dependency error metric for the AIOps dashboards
const { dependencyErrorsTotal } = require('./metrics');
const { HttpError } = require('./service');

async function callService(dependency, url, { method = 'GET', body, req, timeoutMs = 5000, headers = {} } = {}) {
  const h = { 'Content-Type': 'application/json', ...headers };
  if (req?.id) h['X-Request-Id'] = req.id;
  if (req?.headers?.authorization && !h.Authorization) h.Authorization = req.headers.authorization;

  let res;
  try {
    res = await fetch(url, {
      method,
      headers: h,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err) {
    dependencyErrorsTotal.inc({ dependency });
    throw new HttpError(503, `${dependency} is unreachable`, { cause: err.message });
  }

  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    if (res.status >= 500) dependencyErrorsTotal.inc({ dependency });
    // Pass 4xx through (e.g. out of stock), map 5xx to 502/503 for the caller.
    const status = res.status >= 500 ? (res.status === 503 ? 503 : 502) : res.status;
    throw new HttpError(status, data?.error || `${dependency} returned ${res.status}`);
  }
  return data;
}

module.exports = { callService };
