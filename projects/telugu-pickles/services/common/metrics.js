// Prometheus metrics shared by every service.
// RED metrics (Rate, Errors, Duration) + Node.js runtime metrics + business counters.
const client = require('prom-client');

const register = new client.Registry();

function initMetrics(serviceName) {
  register.setDefaultLabels({ app: serviceName });
  client.collectDefaultMetrics({ register });
}

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

const httpRequestsInFlight = new client.Gauge({
  name: 'http_requests_in_flight',
  help: 'HTTP requests currently being served',
  registers: [register],
});

// Business metrics (used on the Grafana "Business" row and by the AIOps agent)
const ordersPlacedTotal = new client.Counter({
  name: 'tp_orders_placed_total',
  help: 'Orders placed, by final status',
  labelNames: ['status', 'payment_method'],
  registers: [register],
});

const orderValueRupeesTotal = new client.Counter({
  name: 'tp_order_value_rupees_total',
  help: 'Sum of confirmed order totals in INR',
  registers: [register],
});

const paymentsTotal = new client.Counter({
  name: 'tp_payments_total',
  help: 'Payment attempts, by method and result',
  labelNames: ['method', 'result'],
  registers: [register],
});

const dependencyErrorsTotal = new client.Counter({
  name: 'tp_dependency_errors_total',
  help: 'Failed calls to other services or the database',
  labelNames: ['dependency'],
  registers: [register],
});

// Express middleware: records RED metrics using the *route template*
// (e.g. /products/:slug) so label cardinality stays low.
function metricsMiddleware(req, res, next) {
  if (req.path === '/metrics' || req.path.startsWith('/health')) return next();
  const end = httpRequestDuration.startTimer();
  httpRequestsInFlight.inc();
  res.on('finish', () => {
    const route = req.route
      ? `${req.baseUrl || ''}${req.route.path}`
      : res.locals.routeLabel || 'unmatched';
    const labels = { method: req.method, route, status_code: String(res.statusCode) };
    httpRequestsTotal.inc(labels);
    end(labels);
    httpRequestsInFlight.dec();
  });
  next();
}

async function metricsHandler(_req, res) {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
}

module.exports = {
  register,
  initMetrics,
  metricsMiddleware,
  metricsHandler,
  ordersPlacedTotal,
  orderValueRupeesTotal,
  paymentsTotal,
  dependencyErrorsTotal,
};
