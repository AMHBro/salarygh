import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function databaseUrl() {
  if (process.env.DATABASE_URL) {
    return process.env.DATABASE_URL;
  }

  const env = readFileSync(new URL('../.env', import.meta.url), 'utf8');
  const match = env.match(/^DATABASE_URL=(?:"([^"]+)"|(\S+))/m);
  if (!match) {
    throw new Error('DATABASE_URL is missing');
  }
  return match[1] || match[2];
}

const url = new URL(databaseUrl());
const directory = fileURLToPath(new URL('../backups', import.meta.url));
mkdirSync(directory, { recursive: true });

const now = new Date();
const stamp = [
  now.getFullYear(),
  String(now.getMonth() + 1).padStart(2, '0'),
  String(now.getDate()).padStart(2, '0'),
  String(now.getHours()).padStart(2, '0'),
  String(now.getMinutes()).padStart(2, '0'),
].join('');
const file = path.join(directory, `sayler-postgres-${stamp}.dump`);

const result = spawnSync(
  'pg_dump',
  ['--format=custom', '--no-owner', '--file', file, '--dbname', url.toString()],
  { stdio: 'inherit' },
);

if (result.error) {
  console.error('pg_dump غير موجود. ثبّت أدوات PostgreSQL ثم أعد الأمر npm run db:backup.');
  process.exit(1);
}

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

console.log(`تمت نسخة الخادم: ${file}`);
