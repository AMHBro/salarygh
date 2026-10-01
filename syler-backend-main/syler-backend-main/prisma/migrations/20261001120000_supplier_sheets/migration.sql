CREATE TABLE IF NOT EXISTS "supplier_sheets" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "supplier_id" UUID NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "image_url" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "supplier_sheets_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "supplier_sheets_supplier_id_idx" ON "supplier_sheets"("supplier_id");
CREATE INDEX IF NOT EXISTS "supplier_sheets_created_at_idx" ON "supplier_sheets"("created_at");

ALTER TABLE "supplier_sheets"
ADD CONSTRAINT "supplier_sheets_supplier_id_fkey"
FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE CASCADE ON UPDATE CASCADE;
