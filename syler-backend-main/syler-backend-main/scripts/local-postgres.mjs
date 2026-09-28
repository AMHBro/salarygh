import EmbeddedPostgres from 'embedded-postgres';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const databaseDir = fileURLToPath(new URL('../pgdata-utf8', import.meta.url));
const port = 54329;
const user = 'sayler';
const password = 'sayler_local_only';
const database = 'sayler';

function assertLocalEnv() {
  const env = readFileSync(new URL('../.env', import.meta.url), 'utf8');
  const urls = [...env.matchAll(/^(DATABASE_URL|DIRECT_URL)=(?:"([^"]+)"|(\S+))/gm)].map(
    (match) => match[2] || match[3],
  );

  if (urls.length !== 2) {
    throw new Error('DATABASE_URL and DIRECT_URL must both be set in .env');
  }

  for (const url of urls) {
    const parsed = new URL(url);
    const host = parsed.hostname;
    if (host !== '127.0.0.1' && host !== 'localhost') {
      throw new Error(`Refusing non-local database host: ${host}`);
    }
    if (parsed.port !== String(port) || parsed.pathname !== `/${database}`) {
      throw new Error('Database URL does not match the local sayler database');
    }
  }
}

assertLocalEnv();

const postgres = new EmbeddedPostgres({
  databaseDir,
  user,
  password,
  port,
  persistent: true,
  initdbFlags: ['--encoding=UTF8', '--locale=C'],
});

try {
  await postgres.initialise();
} catch (error) {
  const message = String(error);
  if (!existsSync(databaseDir) || !/already|exist/i.test(message)) {
    throw error;
  }
}

await postgres.start();

try {
  await postgres.createDatabase(database);
} catch (error) {
  const message = String(error);
  if (!/already|exist/i.test(message)) {
    throw error;
  }
}

const client = postgres.getPgClient(database);
await client.connect();
await client.query('CREATE EXTENSION IF NOT EXISTS pgcrypto');
await client.end();

console.log(`Local PostgreSQL ready on 127.0.0.1:${port}/${database}`);
await new Promise(() => {});
