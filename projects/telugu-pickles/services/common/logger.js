// Structured JSON logger.
// One JSON object per line -> easy to search in CloudWatch Logs Insights
// and easy for the Bedrock AIOps agent (Kira) to reason about.
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const minLevel = LEVELS[(process.env.LOG_LEVEL || 'info').toLowerCase()] || LEVELS.info;

function createLogger(service) {
  const write = (level, msg, fields = {}) => {
    if (LEVELS[level] < minLevel) return;
    const entry = {
      ts: new Date().toISOString(),
      level: level.toUpperCase(),
      service,
      msg,
      ...fields,
    };
    if (fields.err instanceof Error) {
      entry.err = { name: fields.err.name, message: fields.err.message, stack: fields.err.stack };
    }
    const line = JSON.stringify(entry);
    if (level === 'error' || level === 'warn') process.stderr.write(line + '\n');
    else process.stdout.write(line + '\n');
  };
  return {
    debug: (m, f) => write('debug', m, f),
    info: (m, f) => write('info', m, f),
    warn: (m, f) => write('warn', m, f),
    error: (m, f) => write('error', m, f),
  };
}

module.exports = { createLogger };
