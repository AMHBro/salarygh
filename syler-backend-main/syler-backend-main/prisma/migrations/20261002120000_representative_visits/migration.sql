CREATE TABLE IF NOT EXISTS "representative_visits" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "representative_id" UUID NOT NULL,
    "customer_id" UUID,
    "status" VARCHAR(20) NOT NULL,
    "started_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ended_at" TIMESTAMPTZ(6),
    "postponed_until" TIMESTAMPTZ(6),
    "latitude" DECIMAL(9, 6),
    "longitude" DECIMAL(9, 6),
    "geofence_radius_m" INTEGER NOT NULL DEFAULT 150,
    "notes" TEXT,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "representative_visits_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "idx_rep_visits_rep" ON "representative_visits"("representative_id");
CREATE INDEX IF NOT EXISTS "idx_rep_visits_customer" ON "representative_visits"("customer_id");
CREATE INDEX IF NOT EXISTS "idx_rep_visits_status" ON "representative_visits"("status");

ALTER TABLE "representative_visits"
ADD CONSTRAINT "representative_visits_representative_id_fkey"
FOREIGN KEY ("representative_id") REFERENCES "representatives"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE "representative_visits"
ADD CONSTRAINT "representative_visits_customer_id_fkey"
FOREIGN KEY ("customer_id") REFERENCES "customers"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
