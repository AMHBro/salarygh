import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import EmbeddedPostgres from 'embedded-postgres';

function ageDays(invoiceDate, now) {
  const start = Date.UTC(
    invoiceDate.getUTCFullYear(),
    invoiceDate.getUTCMonth(),
    invoiceDate.getUTCDate(),
  );
  const end = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return Math.max(0, Math.round((end - start) / 86_400_000));
}

test('PostgreSQL sales pipeline deducts stock and ages the unpaid invoice', async () => {
  const port = 54341;
  const postgres = new EmbeddedPostgres({
    databaseDir: mkdtempSync(join(tmpdir(), 'sayler-pipeline-')),
    user: 'sayler',
    password: 'sayler_local_only',
    port,
    persistent: false,
  });
  await postgres.initialise();
  await postgres.start();
  await postgres.createDatabase('sayler_pipeline');
  const client = postgres.getPgClient('sayler_pipeline');
  await client.connect();
  try {
    await client.query(`
      CREATE TABLE customers (
        id uuid PRIMARY KEY,
        balance numeric(15, 2) NOT NULL
      );
      CREATE TABLE stock_levels (
        variant_id uuid PRIMARY KEY,
        quantity_on_hand numeric(15, 3) NOT NULL
      );
      CREATE TABLE sales_invoices (
        id uuid PRIMARY KEY,
        customer_id uuid NOT NULL,
        invoice_number text NOT NULL,
        total numeric(15, 2) NOT NULL,
        due_amount numeric(15, 2) NOT NULL,
        invoice_date timestamptz NOT NULL,
        status text NOT NULL
      );
    `);
    const customerId = '22222222-2222-2222-2222-222222222222';
    const variantId = '33333333-3333-3333-3333-333333333333';
    const invoiceId = '55555555-5555-5555-5555-555555555555';
    await client.query('BEGIN');
    await client.query('INSERT INTO customers (id, balance) VALUES ($1, 0)', [customerId]);
    await client.query(
      'INSERT INTO stock_levels (variant_id, quantity_on_hand) VALUES ($1, 10)',
      [variantId],
    );
    await client.query(
      `INSERT INTO sales_invoices
        (id, customer_id, invoice_number, total, due_amount, invoice_date, status)
       VALUES ($1, $2, 'INV-PIPE', 10, 10, '2026-08-01T00:00:00Z', 'PARTIAL')`,
      [invoiceId, customerId],
    );
    await client.query(
      'UPDATE stock_levels SET quantity_on_hand = quantity_on_hand - 2 WHERE variant_id = $1',
      [variantId],
    );
    await client.query('UPDATE customers SET balance = balance + 10 WHERE id = $1', [customerId]);
    await client.query('COMMIT');

    const stock = await client.query(
      'SELECT quantity_on_hand FROM stock_levels WHERE variant_id = $1',
      [variantId],
    );
    const balance = await client.query('SELECT balance FROM customers WHERE id = $1', [customerId]);
    const invoices = await client.query(
      `SELECT invoice_number, due_amount, invoice_date
       FROM sales_invoices
       WHERE customer_id = $1 AND due_amount > 0 AND status <> 'CANCELLED'`,
      [customerId],
    );
    const days = ageDays(new Date(invoices.rows[0].invoice_date), new Date('2026-10-02T00:00:00.000Z'));

    assert.equal(Number(stock.rows[0].quantity_on_hand), 8);
    assert.equal(Number(balance.rows[0].balance), 10);
    assert.equal(invoices.rows.length, 1);
    assert.equal(invoices.rows[0].invoice_number, 'INV-PIPE');
    assert.equal(days, 62);
    assert.ok(days > 60 && days <= 90);
  } finally {
    await client.end();
    await postgres.stop();
  }
});
