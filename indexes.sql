-- 1. B-tree: звичайні індекси за зовнішніми ключами
-- Вибірка товарів певної категорії
CREATE INDEX IF NOT EXISTS "IX_Products_CategoryId"   ON "Store"."Products" ("CategoryId");
-- Підзамовлення магазину (vw_store_sales_summary, fn_store_revenue)
CREATE INDEX IF NOT EXISTS "IX_StoreOrders_StoreId"   ON "Store"."StoreOrders" ("StoreId");

-- 2. B-tree складений: журнал змін за таблицею та записом
CREATE INDEX IF NOT EXISTS "IX_AuditLogs_Table_Record" ON "Store"."AuditLogs" ("TableName", "RecordId");

-- 3. B-tree частковий (враховує soft delete): індексуються лише активні записи
-- Каталог: активні товари магазину в категорії
CREATE INDEX IF NOT EXISTS "IX_Products_Active_Store_Category"
    ON "Store"."Products" ("StoreId", "CategoryId") WHERE "IsDeleted" = false;

-- Активні відгуки товару (fn_product_avg_rating, vw_active_products)
CREATE INDEX IF NOT EXISTS "IX_Reviews_ProductId_Active"
    ON "Store"."Reviews" ("ProductId") WHERE "IsDeleted" = false;

-- 4. B-tree частковий унікальний: унікальність лише серед невидалених записів.
-- Назву магазину чи код купона, що належали видаленому запису, можна використати знову.
CREATE UNIQUE INDEX IF NOT EXISTS "UX_Stores_Name_Active"
    ON "Store"."Stores" ("Name") WHERE "IsDeleted" = false;

CREATE UNIQUE INDEX IF NOT EXISTS "UX_Coupons_Code_Active"
    ON "Store"."Coupons" ("Code") WHERE "IsDeleted" = false;

-- 5. GIN: повнотекстовий пошук товарів за назвою та описом
CREATE INDEX IF NOT EXISTS "IX_Products_Search_GIN"
    ON "Store"."Products"
    USING GIN (to_tsvector('simple', "Name" || ' ' || "Description"));