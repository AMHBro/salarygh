-- يُطبَّق أيضاً عند إقلاع الخادم من PrismaService.
-- NOT VALID يفحص الصفوف الجديدة والتحديثات، ويتجاوز الأرصدة السالبة القديمة.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'stock_levels_on_hand_nonnegative'
    ) THEN
        ALTER TABLE stock_levels
            ADD CONSTRAINT stock_levels_on_hand_nonnegative
            CHECK (quantity_on_hand >= 0) NOT VALID;
    END IF;
END $$;
