// Runs the actual sibling backend + SDK against its existing Postman fixture.
// No .env or real provider key is read.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const backend = resolve(process.env.BACKEND_DIR ?? '../jangjak_diary_backend');
const load = (file: string) => import(pathToFileURL(resolve(backend, file)).href);
const { buildApp } = await load('src/app.ts');
const { loadConfig } = await load('src/config.ts');
const { createAnthropicLlm } = await load('src/services/llm.ts');
const llm = createAnthropicLlm({
  apiKey: 'simulation-only-placeholder',
  model: 'claude-haiku-5-5',
  timeoutMs: 2000,
  baseURL: process.env.SIMULATION_URL ?? 'http://127.0.0.1:4900/anthropic',
});
// Enough fixture calls for the integration suite; production remains 5/day.
const app = await buildApp(loadConfig({ AI_DAILY_LIMIT: '20' }), llm);
await app.listen({ host: '127.0.0.1', port: Number(process.env.SIMULATION_API_PORT ?? 3001) });
console.log('Local simulation backend ready on 127.0.0.1:3001 (provider fixture, no live AI).');
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, async () => { await app.close(); process.exit(0); });
}
