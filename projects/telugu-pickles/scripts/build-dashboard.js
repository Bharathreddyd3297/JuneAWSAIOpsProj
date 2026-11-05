// Generates the Grafana dashboard JSON used locally AND on EKS (as a ConfigMap).
//   node scripts/build-dashboard.js
const fs = require('fs');
const path = require('path');

const DS = { type: 'prometheus', uid: 'prometheus' };
let id = 1;
const ts = (title, exprs, unit, x, y, w = 12, h = 8) => ({
  id: id++, type: 'timeseries', title, datasource: DS, gridPos: { x, y, w, h },
  fieldConfig: { defaults: { unit, custom: { lineWidth: 2, fillOpacity: 12, showPoints: 'never' } }, overrides: [] },
  options: { legend: { displayMode: 'table', placement: 'right', calcs: ['lastNotNull', 'max'] }, tooltip: { mode: 'multi' } },
  targets: exprs.map(([expr, legendFormat], i) => ({ refId: String.fromCharCode(65 + i), datasource: DS, expr, legendFormat })),
});
const stat = (title, expr, unit, color, x, y, w = 6, h = 4) => ({
  id: id++, type: 'stat', title, datasource: DS, gridPos: { x, y, w, h },
  fieldConfig: { defaults: { unit, color: { mode: 'fixed', fixedColor: color }, decimals: 0 }, overrides: [] },
  options: { colorMode: 'background', graphMode: 'area', reduceOptions: { calcs: ['lastNotNull'] } },
  targets: [{ refId: 'A', datasource: DS, expr }],
});
const row = (title, y) => ({ id: id++, type: 'row', title, collapsed: false, gridPos: { x: 0, y, w: 24, h: 1 }, panels: [] });

const A = 'app=~"$app"';
const panels = [
  row('Golden signals', 0),
  ts('Request rate (req/s)', [[`sum by (app) (rate(http_requests_total{${A}}[1m]))`, '{{app}}']], 'reqps', 0, 1),
  ts('Error rate — 5xx %', [[`100 * sum by (app) (rate(http_requests_total{${A},status_code=~"5.."}[5m])) / clamp_min(sum by (app) (rate(http_requests_total{${A}}[5m])), 1e-9)`, '{{app}}']], 'percent', 12, 1),
  ts('Latency p95', [[`histogram_quantile(0.95, sum by (le, app) (rate(http_request_duration_seconds_bucket{${A}}[5m])))`, '{{app}} p95']], 's', 0, 9),
  ts('Dependency errors (calls to other services / DB)', [[`sum by (app, dependency) (rate(tp_dependency_errors_total{${A}}[5m]))`, '{{app}} → {{dependency}}']], 'ops', 12, 9),
  row('Business — Telugu Pickles', 17),
  stat('Orders confirmed', 'sum(increase(tp_orders_placed_total{status="CONFIRMED"}[$__range]))', 'none', '#2E7D32', 0, 18),
  stat('Checkouts failed at payment', 'sum(increase(tp_orders_placed_total{status="PAYMENT_FAILED"}[$__range]))', 'none', '#C62828', 6, 18),
  stat('Revenue (INR)', 'sum(increase(tp_order_value_rupees_total[$__range]))', 'currencyINR', '#1B5E20', 12, 18),
  stat('Payment success %', '100 * sum(increase(tp_payments_total{result!="DECLINED"}[$__range])) / clamp_min(sum(increase(tp_payments_total[$__range])), 1)', 'percent', '#8E1414', 18, 18),
  ts('Payments by result', [['sum by (method, result) (rate(tp_payments_total[5m]))', '{{method}} {{result}}']], 'ops', 0, 22),
  ts('Orders by status', [['sum by (status) (rate(tp_orders_placed_total[5m]))', '{{status}}']], 'ops', 12, 22),
  row('Node.js runtime', 30),
  ts('Heap used', [[`nodejs_heap_size_used_bytes{${A}}`, '{{app}}']], 'bytes', 0, 31, 8),
  ts('Event loop lag p99', [[`nodejs_eventloop_lag_p99_seconds{${A}}`, '{{app}}']], 's', 8, 31, 8),
  ts('CPU (process)', [[`rate(process_cpu_seconds_total{${A}}[1m])`, '{{app}}']], 'percentunit', 16, 31, 8),
];

const dashboard = {
  uid: 'telugu-pickles',
  title: 'Telugu Pickles — Service Overview',
  tags: ['telugu-pickles', 'aiops'],
  timezone: 'browser',
  schemaVersion: 39,
  refresh: '10s',
  time: { from: 'now-1h', to: 'now' },
  templating: {
    list: [{
      name: 'app', label: 'Service', type: 'query', datasource: DS,
      query: { query: 'label_values(http_requests_total, app)', refId: 'app' },
      definition: 'label_values(http_requests_total, app)',
      includeAll: true, multi: true, allValue: '.*', current: { text: 'All', value: '$__all' }, refresh: 2,
    }],
  },
  panels,
};

const out = path.join(__dirname, '..', 'observability', 'grafana', 'dashboards', 'telugu-pickles.json');
const gitopsOut = path.join(__dirname, '..', '..', '..', 'gitops', 'k8s', 'monitoring', 'telugu-pickles-dashboard.json');
for (const f of [out, gitopsOut]) {
  fs.writeFileSync(f, JSON.stringify(dashboard, null, 2));
  console.log('wrote', f, `(${panels.length} panels)`);
}
