--Тестові дані: 50 магазинів, 100 категорій, 100 000 товарів 
DO $$
DECLARE
    v_owner  integer;
    v_stores integer[];
    v_cats   integer[];
BEGIN
    INSERT INTO "Store"."Users" ("RoleId", "IdentityUserId")
    VALUES ((SELECT "Id" FROM "Store"."Roles" WHERE "Name" = 'Seller'), 'index-demo-owner')
    ON CONFLICT ("IdentityUserId") DO NOTHING;
    SELECT "Id" INTO v_owner FROM "Store"."Users" WHERE "IdentityUserId" = 'index-demo-owner';

    INSERT INTO "Store"."Stores" ("OwnerId", "Name", "ContactEmail")
    SELECT v_owner, 'IdxDemo Store ' || g, 'demo@example.com' FROM generate_series(1, 50) g;

    INSERT INTO "Store"."Categories" ("Name")
    SELECT 'IdxDemo Cat ' || g FROM generate_series(1, 100) g;

    v_stores := ARRAY(SELECT "Id" FROM "Store"."Stores"     WHERE "Name" LIKE 'IdxDemo Store %' ORDER BY "Id");
    v_cats   := ARRAY(SELECT "Id" FROM "Store"."Categories" WHERE "Name" LIKE 'IdxDemo Cat %'   ORDER BY "Id");

    -- на час масового завантаження вимикаємо тригери, щоб не заповнювати журнал змін
    ALTER TABLE "Store"."Products" DISABLE TRIGGER USER;
    INSERT INTO "Store"."Products" ("StoreId", "CategoryId", "Name", "Description", "Price")
    SELECT v_stores[1 + g % 50],              -- магазин і категорія розподілені незалежно:
           v_cats[1 + (g / 50) % 100],        -- кожна пара (магазин, категорія) має приблизно по 20 товарів
           'IdxDemo Товар ' || g,
           'Опис товару код' || g || ' ' || md5(g::text),
           round((random() * 1000)::numeric, 2)
    FROM generate_series(1, 100000) g;
    ALTER TABLE "Store"."Products" ENABLE TRIGGER USER;
END $$;

ANALYZE "Store"."Products";

SELECT count(*) AS products_total FROM "Store"."Products";

--КРОК 2. Видаляємо індекси
DROP INDEX IF EXISTS "Store"."IX_Products_Active_Store_Category";
DROP INDEX IF EXISTS "Store"."IX_Products_CategoryId";
DROP INDEX IF EXISTS "Store"."IX_Products_Search_GIN";

-- 2а. Товари магазину в категорії (запит каталогу)
EXPLAIN ANALYZE
SELECT "Id", "Name", "Price" FROM "Store"."Products"
WHERE "StoreId"    = (SELECT "Id" FROM "Store"."Stores"     WHERE "Name" = 'IdxDemo Store 1' AND "IsDeleted" = false)
  AND "CategoryId" = (SELECT "Id" FROM "Store"."Categories" WHERE "Name" = 'IdxDemo Cat 1')
  AND "IsDeleted"  = false;

-- 2б. Повнотекстовий пошук товару
EXPLAIN ANALYZE
SELECT "Id", "Name" FROM "Store"."Products"
WHERE to_tsvector('simple', "Name" || ' ' || "Description") @@ plainto_tsquery('simple', 'код77777');

--КРОК 3. Створюємо індекси 
CREATE INDEX IF NOT EXISTS "IX_Products_CategoryId"   ON "Store"."Products" ("CategoryId");

CREATE INDEX IF NOT EXISTS "IX_Products_Active_Store_Category"
    ON "Store"."Products" ("StoreId", "CategoryId") WHERE "IsDeleted" = false;

CREATE INDEX IF NOT EXISTS "IX_Products_Search_GIN"
    ON "Store"."Products" USING GIN (to_tsvector('simple', "Name" || ' ' || "Description"));

ANALYZE "Store"."Products";

--КРОК 4. Після створення індексів (ті самі запити)
EXPLAIN ANALYZE
SELECT "Id", "Name", "Price" FROM "Store"."Products"
WHERE "StoreId"    = (SELECT "Id" FROM "Store"."Stores"     WHERE "Name" = 'IdxDemo Store 1' AND "IsDeleted" = false)
  AND "CategoryId" = (SELECT "Id" FROM "Store"."Categories" WHERE "Name" = 'IdxDemo Cat 1')
  AND "IsDeleted"  = false;

EXPLAIN ANALYZE
SELECT "Id", "Name" FROM "Store"."Products"
WHERE to_tsvector('simple', "Name" || ' ' || "Description") @@ plainto_tsquery('simple', 'код77777');

--КРОК 5. Частковий унікальний індекс UX_Stores_Name_Active
-- 5а. Створюємо магазин
DO $$
DECLARE
    v_owner integer; v_id integer;
BEGIN
    SELECT "Id" INTO v_owner FROM "Store"."Users" WHERE "IdentityUserId" = 'index-demo-owner';
    CALL "Store".sp_create_store(v_owner, 'IdxDemo Unique', 'тест унікальності', 'u@example.com', v_id);
END $$;

-- 5б. Магазин з такою самою назвою, поки перший активний: помилка (unique violation)
DO $$
DECLARE
    v_owner integer; v_id integer;
BEGIN
    SELECT "Id" INTO v_owner FROM "Store"."Users" WHERE "IdentityUserId" = 'index-demo-owner';
    CALL "Store".sp_create_store(v_owner, 'IdxDemo Unique', 'дублікат', 'u@example.com', v_id);
END $$;

-- 5в. М'яко видаляємо перший магазин і створюємо магазин з тією самою назвою: успішно
DO $$
DECLARE
    v_owner integer; v_old integer; v_id integer;
BEGIN
    SELECT "Id" INTO v_owner FROM "Store"."Users" WHERE "IdentityUserId" = 'index-demo-owner';
    SELECT "Id" INTO v_old FROM "Store"."Stores" WHERE "Name" = 'IdxDemo Unique' AND "IsDeleted" = false;
    CALL "Store".sp_soft_delete_store(v_old);
    CALL "Store".sp_create_store(v_owner, 'IdxDemo Unique', 'після видалення', 'u@example.com', v_id);
END $$;

SELECT "Id", "Name", "IsDeleted" FROM "Store"."Stores" WHERE "Name" = 'IdxDemo Unique' ORDER BY "Id";

--КРОК 6. Перелік індексів, створених скриптом іndexes.sql 
SELECT tablename AS table_name, indexname AS index_name, indexdef AS definition
FROM pg_indexes
WHERE schemaname = 'Store' AND (indexname LIKE 'IX\_%' OR indexname LIKE 'UX\_%')
ORDER BY tablename, indexname;

-- Розмір індексів
SELECT indexrelname AS index_name, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'Store' AND (indexrelname LIKE 'IX\_%' OR indexrelname LIKE 'UX\_%')
ORDER BY pg_relation_size(indexrelid) DESC;

--Очищення текстових даних
DELETE FROM "Store"."Products"   WHERE "Name" LIKE 'IdxDemo%';
DELETE FROM "Store"."StoreStaff" WHERE "StoreId" IN (SELECT "Id" FROM "Store"."Stores" WHERE "Name" LIKE 'IdxDemo%');
DELETE FROM "Store"."Stores"     WHERE "Name" LIKE 'IdxDemo%';
DELETE FROM "Store"."Categories" WHERE "Name" LIKE 'IdxDemo%';
DELETE FROM "Store"."AuditLogs"  WHERE "TableName" = 'Stores' AND "NewData" ->> 'Name' LIKE 'IdxDemo%';
DELETE FROM "Store"."Users"      WHERE "IdentityUserId" = 'index-demo-owner';