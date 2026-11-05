// Tiny service "framework" so all six services behave identically:
//   - request id propagation (X-Request-Id) for cross-service tracing in logs
//   - JSON access logs
//   - Prometheus /metrics
//   - /health/live (process up) and /health/ready (dependencies OK)
//   - optional chaos injection for the AIOps demo
//   - consistent JSON errors and graceful shutdown on SIGTERM (Kubernetes)
const crypto = require('crypto');
const express = require('express');
const { createLogger } = require('./logger');
const { initMetrics, metricsMiddleware, metricsHandler } = require('./metrics');

class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

// async handler wrapper for Express 4
const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function createService({ name, jsonBody = true }) {
  const log = createLogger(name);
  initMetrics(name);
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', true);

  let ready = false;
  let readyCheck = async () => true;

  // request id + access log
  app.use((req, res, next) => {
    req.id = req.headers['x-request-id'] || crypto.randomUUID();
    res.setHeader('X-Request-Id', req.id);
    const start = process.hrtime.bigint();
    res.on('finish', () => {
      if (req.path.startsWith('/health') || req.path === '/metrics') return;
      const ms = Number(process.hrtime.bigint() - start) / 1e6;
      const level = res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info';
      log[level]('request', {
        requestId: req.id,
        method: req.method,
        path: req.originalUrl,
        status: res.statusCode,
        durationMs: Math.round(ms),
        userId: req.user?.id,
      });
    });
    next();
  });

  app.use(metricsMiddleware);
  app.get('/metrics', metricsHandler);
  app.get('/health/live', (_req, res) => res.json({ status: 'ok', service: name }));
  app.get('/health/ready', async (_req, res) => {
    try {
      if (!ready) throw new Error('starting');
      await readyCheck();
      res.json({ status: 'ready', service: name });
    } catch (err) {
      res.status(503).json({ status: 'not-ready', service: name, reason: err.message });
    }
  });

  // Chaos injection (AIOps demo). Off by default.
  //   CHAOS_ERROR_RATE=0.3   -> ~30% of requests fail with 503
  //   CHAOS_LATENCY_MS=1500  -> adds latency to every request
  const errorRate = Number(process.env.CHAOS_ERROR_RATE || 0);
  const latencyMs = Number(process.env.CHAOS_LATENCY_MS || 0);
  if (errorRate > 0 || latencyMs > 0) {
    log.warn('CHAOS MODE ENABLED', { errorRate, latencyMs });
    app.use(async (req, res, next) => {
      if (latencyMs > 0) await new Promise((r) => setTimeout(r, latencyMs));
      if (errorRate > 0 && Math.random() < errorRate) {
        log.error('chaos: injected failure', { requestId: req.id, path: req.originalUrl });
        return res.status(503).json({ error: `${name} temporarily unavailable (chaos)` });
      }
      next();
    });
  }

  if (jsonBody) app.use(express.json({ limit: '100kb' }));

  function finalize() {
    app.use((req, res) => res.status(404).json({ error: 'Not found', path: req.originalUrl }));
    // eslint-disable-next-line no-unused-vars
    app.use((err, req, res, _next) => {
      const status = err.status || (err.type === 'entity.parse.failed' ? 400 : 500);
      if (status >= 500) log.error('unhandled error', { requestId: req.id, err });
      res.status(status).json({ error: status >= 500 ? 'Internal server error' : err.message, details: err.details });
    });
  }

  async function start({ port, init, check }) {
    finalize();
    const server = app.listen(port, '0.0.0.0', () => log.info('listening', { port }));
    try {
      if (init) await init();
      if (check) readyCheck = check;
      ready = true;
      log.info('service ready');
    } catch (err) {
      log.error('startup failed', { err });
      process.exit(1);
    }
    const shutdown = (signal) => {
      log.info('shutting down', { signal });
      ready = false;
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(0), 10000).unref();
    };
    process.on('SIGTERM', shutdown);
    process.on('SIGINT', shutdown);
    return server;
  }

  return { app, log, start, HttpError };
}

module.exports = { createService, HttpError, ah };
