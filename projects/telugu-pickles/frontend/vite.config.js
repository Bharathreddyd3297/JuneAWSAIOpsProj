import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// In dev (npm run dev) the browser calls /api on :5173 and Vite proxies to the gateway.
// In containers nginx does the same job, so the app ALWAYS uses relative /api URLs
// (no build-time API URL baked into the bundle -> one image works in every environment).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { '/api': process.env.GATEWAY_URL || 'http://localhost:8080' },
  },
});
