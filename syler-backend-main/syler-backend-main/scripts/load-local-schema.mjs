import { readFileSync } from 'node:fs';
import pg from 'pg';

const connectionString =
  'postgresql://sayler:sayler_local_only@127.0.0.1:54329/sayler';
const parsed = new URL(connectionString);

if (parsed.hostname !== '127.0.0.1' || parsed.port !== '54329') {
  throw new Error('Refusing to load schema into a non-local database');
}

const client = new pg.Client({ connectionString });
await client.connect();

const identity = await client.query(
  'SELECT current_database() AS db, inet_server_addr()::text AS addr',
);
const { db, addr } = identity.rows[0];
if (db !== 'sayler' || !String(addr).startsWith('127.0.0.1')) {
  await client.end();
  throw new Error(`Refusing unexpected database target ${addr}/${db}`);
}

await client.query('DROP SCHEMA public CASCADE');
await client.query('CREATE SCHEMA public');
await client.query('CREATE EXTENSION IF NOT EXISTS pgcrypto');

const source = readFileSync(
  new URL('../../../sayler_schema.sql', import.meta.url),
  'utf8',
);
const sql = source
  .split(/\r?\n/)
  .filter((line) => {
    const trimmed = line.trim();
    if (trimmed.startsWith('\\')) return false;
    if (/OWNER TO|DEFAULT PRIVILEGES|GRANT USAGE ON SCHEMA/i.test(line)) {
      return false;
    }
    if (/"postgres"|"anon"|"authenticated"|"service_role"|"pg_database_owner"/.test(line)) {
      return false;
    }
    return true;
  })
  .join('\n');

await client.query(sql);

await client.query(`
  ALTER TABLE public.representatives
    ALTER COLUMN commission_rate TYPE numeric(15,2);
  ALTER TABLE public.representatives
    ADD COLUMN IF NOT EXISTS allowed_prices character varying(200)
      NOT NULL DEFAULT 'wholesale,representative,retail';
`);

const dataPath = new URL('../../../sayler_data.sql', import.meta.url);
await loadCopyDump(client, readFileSync(dataPath, 'utf8'));

await client.end();
console.log('Local schema and data loaded into 127.0.0.1:54329/sayler');

function unescapeCopyField(field) {
  if (field === '\\N') return null;
  let out = '';
  for (let i = 0; i < field.length; i += 1) {
    if (field[i] === '\\' && i + 1 < field.length) {
      const next = field[(i += 1)];
      if (next === 'n') out += '\n';
      else if (next === 'r') out += '\r';
      else if (next === 't') out += '\t';
      else if (next === 'b') out += '\b';
      else if (next === 'f') out += '\f';
      else out += next;
    } else {
      out += field[i];
    }
  }
  return out;
}

async function loadCopyDump(client, source) {
  const lines = source.split(/\r?\n/);
  let copy = null;
  for (const line of lines) {
    const trimmed = line.trim();
    if (!copy) {
      if (
        trimmed.startsWith('--') ||
        trimmed === '' ||
        trimmed.startsWith('\\')
      ) {
        continue;
      }
      const match = trimmed.match(
        /^COPY\s+"public"\."([^"]+)"\s+\((.+)\)\s+FROM\s+stdin;$/i,
      );
      if (match) {
        copy = {
          table: match[1],
          columns: [...match[2].matchAll(/"([^"]+)"/g)].map((item) => item[1]),
          rows: [],
        };
        continue;
      }
      if (/^(SET|SELECT|RESET)\b/i.test(trimmed)) {
        await client.query(trimmed);
      }
      continue;
    }
    if (trimmed === '\\.') {
      if (copy.rows.length > 0) {
        const placeholders = copy.columns.map((_, index) => `$${index + 1}`);
        const insert = `INSERT INTO public."${copy.table}" (${copy.columns
          .map((column) => `"${column}"`)
          .join(', ')}) VALUES (${placeholders.join(', ')})`;
        for (const values of copy.rows) {
          await client.query(insert, values);
        }
      }
      copy = null;
      continue;
    }
    copy.rows.push(line.split('\t').map(unescapeCopyField));
  }
}
