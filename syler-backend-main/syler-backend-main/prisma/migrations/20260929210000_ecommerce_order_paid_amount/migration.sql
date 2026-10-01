-- Store the cash portion of a representative order.
-- Added debt at checkout is total - paid_amount.
ALTER TABLE "ecommerce_orders" ADD COLUMN "paid_amount" DECIMAL(15,2) NOT NULL DEFAULT 0;
