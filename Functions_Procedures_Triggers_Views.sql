-- 1. ФУНКЦІЇ 

-- F1. Id поточного користувача зі змінної сесії 
CREATE FUNCTION "Store".fn_current_user_id()
RETURNS integer
LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::integer;
$$;

-- F2. Середній рейтинг товару 
CREATE FUNCTION "Store".fn_product_avg_rating(p_product_id integer)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(ROUND(AVG("Rating")::numeric, 2), 0)
    FROM "Store"."Reviews"
    WHERE "ProductId" = p_product_id AND "IsDeleted" = false;
$$;

-- F3. Виручка магазину за період
CREATE FUNCTION "Store".fn_store_revenue(p_store_id integer, p_from timestamptz, p_to timestamptz)
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(so."Subtotal"), 0)
    FROM "Store"."StoreOrders" so
    JOIN "Store"."Orders" o ON o."Id" = so."OrderId"
    WHERE so."StoreId" = p_store_id
      AND so."CurrentStatus" <> 'Cancelled'
      AND o."OrderDate" >= p_from AND o."OrderDate" < p_to;
$$;

-- 2. VIEW 

-- V1. Активні магазини
CREATE VIEW "Store".vw_active_stores AS
SELECT s."Id" AS store_id, s."OwnerId" AS owner_id, s."Name" AS name,
       s."Description" AS description, s."ContactEmail" AS contact_email,
       s."CreatedAt" AS created_at, s."UpdatedAt" AS updated_at, s."UpdatedBy" AS updated_by
FROM "Store"."Stores" s
WHERE s."IsDeleted" = false;

-- V2. Каталог: активні товари + магазин, категорія, рейтинг, залишок
CREATE VIEW "Store".vw_active_products AS
SELECT p."Id" AS product_id, p."Name" AS product_name, p."Description" AS description,
       p."Price" AS price, p."StoreId" AS store_id, s."Name" AS store_name,
       p."CategoryId" AS category_id, c."Name" AS category_name,
       "Store".fn_product_avg_rating(p."Id")                              AS avg_rating,
       (SELECT COUNT(*) FROM "Store"."Reviews" r
         WHERE r."ProductId" = p."Id" AND r."IsDeleted" = false)          AS review_count,
       COALESCE((SELECT SUM(ps."Quantity") FROM "Store"."ProductSizes" ps
                  WHERE ps."ProductId" = p."Id"), 0)                      AS total_stock,
       p."CreatedAt" AS created_at, p."UpdatedAt" AS updated_at, p."UpdatedBy" AS updated_by
FROM "Store"."Products" p
JOIN "Store"."Stores" s     ON s."Id" = p."StoreId"    AND s."IsDeleted" = false
JOIN "Store"."Categories" c ON c."Id" = p."CategoryId" AND c."IsDeleted" = false
WHERE p."IsDeleted" = false;

-- V3. «Кошик» адміністратора: видалені товари (хто і коли видалив)
CREATE VIEW "Store".vw_deleted_products AS
SELECT p."Id" AS product_id, p."Name" AS product_name, p."StoreId" AS store_id,
       s."Name" AS store_name, p."DeletedAt" AS deleted_at, p."DeletedBy" AS deleted_by
FROM "Store"."Products" p
JOIN "Store"."Stores" s ON s."Id" = p."StoreId"
WHERE p."IsDeleted" = true;

-- V4. Статистика продажів по магазинах (скасовані не рахуються)
CREATE VIEW "Store".vw_store_sales_summary AS
SELECT s."Id" AS store_id, s."Name" AS store_name,
       COUNT(so."Id") FILTER (WHERE so."CurrentStatus" <> 'Cancelled')                   AS orders_count,
       COALESCE(SUM(so."Subtotal") FILTER (WHERE so."CurrentStatus" <> 'Cancelled'), 0)  AS revenue
FROM "Store"."Stores" s
LEFT JOIN "Store"."StoreOrders" so ON so."StoreId" = s."Id"
WHERE s."IsDeleted" = false
GROUP BY s."Id", s."Name";

-- 3. ТРИГЕРИ 

-- T1. UPDATE: автоматично ставить UpdatedAt / UpdatedBy
CREATE OR REPLACE FUNCTION "Store".tf_set_updated()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW."UpdatedAt" := now();
    NEW."UpdatedBy" := "Store".fn_current_user_id();
    RETURN NEW;
END $$;

-- T2. UPDATE: IsDeleted false->true ставить DeletedAt/DeletedBy, true->false очищає їх
CREATE OR REPLACE FUNCTION "Store".tf_soft_delete_fields()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW."IsDeleted" AND NOT OLD."IsDeleted" THEN
        NEW."DeletedAt" := now();
        NEW."DeletedBy" := "Store".fn_current_user_id();
    ELSIF NOT NEW."IsDeleted" AND OLD."IsDeleted" THEN
        NEW."DeletedAt" := NULL;
        NEW."DeletedBy" := NULL;
    END IF;
    RETURN NEW;
END $$;

-- T3. INSERT/UPDATE: журнал змін (стан «до» і «після» у JSON)
CREATE OR REPLACE FUNCTION "Store".tf_audit_log()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_action text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO "Store"."AuditLogs" ("TableName", "RecordId", "Action", "OldData", "NewData", "ChangedBy")
        VALUES (TG_TABLE_NAME, (to_jsonb(NEW) ->> 'Id')::integer, 'INSERT', NULL, to_jsonb(NEW),
                "Store".fn_current_user_id());
    ELSE
        v_action := CASE WHEN (to_jsonb(NEW) ->> 'IsDeleted')::boolean
                          AND NOT (to_jsonb(OLD) ->> 'IsDeleted')::boolean
                         THEN 'SOFT_DELETE' ELSE 'UPDATE' END;
        INSERT INTO "Store"."AuditLogs" ("TableName", "RecordId", "Action", "OldData", "NewData", "ChangedBy")
        VALUES (TG_TABLE_NAME, (to_jsonb(NEW) ->> 'Id')::integer, v_action, to_jsonb(OLD), to_jsonb(NEW),
                "Store".fn_current_user_id());
    END IF;
    RETURN NULL;
END $$;

-- Підключення тригерів до таблиць
DO $$
DECLARE
    t text;
BEGIN
    -- T1: таблиці з UpdatedAt / UpdatedBy
    FOREACH t IN ARRAY ARRAY['Users','Stores','Categories','Products','Reviews','Coupons'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_set_updated ON "Store".%I', t);
        EXECUTE format('CREATE TRIGGER trg_set_updated BEFORE UPDATE ON "Store".%I
                        FOR EACH ROW EXECUTE FUNCTION "Store".tf_set_updated()', t);
    END LOOP;

    -- T2: таблиці з soft delete
    FOREACH t IN ARRAY ARRAY['Users','Stores','Categories','Products','Reviews','Coupons'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_soft_delete_fields ON "Store".%I', t);
        EXECUTE format('CREATE TRIGGER trg_soft_delete_fields BEFORE UPDATE ON "Store".%I
                        FOR EACH ROW EXECUTE FUNCTION "Store".tf_soft_delete_fields()', t);
    END LOOP;

    -- T3: журнал змін для ключових сутностей
    FOREACH t IN ARRAY ARRAY['Stores','Products','Reviews'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_log ON "Store".%I', t);
        EXECUTE format('CREATE TRIGGER trg_audit_log AFTER INSERT OR UPDATE ON "Store".%I
                        FOR EACH ROW EXECUTE FUNCTION "Store".tf_audit_log()', t);
    END LOOP;
END $$;

-- 4. ЗБЕРЕЖЕНІ ПРОЦЕДУРИ 

-- P1. Передати в транзакцію Id поточного користувача
CREATE OR REPLACE PROCEDURE "Store".sp_set_current_user(p_user_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('app.current_user_id', COALESCE(p_user_id::text, ''), true);
END $$;

-- P2. Створити магазин (власник автоматично стає працівником з роллю Owner)
CREATE OR REPLACE PROCEDURE "Store".sp_create_store(p_owner_id integer, p_name text, p_description text,
                                                   p_contact_email text, INOUT p_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM "Store"."Users" WHERE "Id" = p_owner_id AND "IsDeleted" = false) THEN
        RAISE EXCEPTION 'Користувача % не знайдено', p_owner_id;
    END IF;
    INSERT INTO "Store"."Stores" ("OwnerId", "Name", "Description", "ContactEmail")
    VALUES (p_owner_id, p_name, p_description, p_contact_email)
    RETURNING "Id" INTO p_id;

    INSERT INTO "Store"."StoreStaff" ("StoreId", "UserId", "StoreRole") VALUES (p_id, p_owner_id, 'Owner');
END $$;

-- P3. М'яко видалити магазин разом з його товарами та працівниками
CREATE OR REPLACE PROCEDURE "Store".sp_soft_delete_store(p_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE "Store"."Stores" SET "IsDeleted" = true WHERE "Id" = p_id AND "IsDeleted" = false;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Магазин % не знайдено або вже видалений', p_id;
    END IF;
    UPDATE "Store"."Products"   SET "IsDeleted" = true WHERE "StoreId" = p_id AND "IsDeleted" = false;
    UPDATE "Store"."StoreStaff" SET "IsDeleted" = true WHERE "StoreId" = p_id AND "IsDeleted" = false;
END $$;

-- P4. Створити товар (перевіряє, що магазин і категорія існують)
CREATE OR REPLACE PROCEDURE "Store".sp_create_product(p_store_id integer, p_category_id integer, p_name text,
                                                     p_description text, p_price numeric, INOUT p_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_price < 0 THEN
        RAISE EXCEPTION 'Ціна не може бути від''ємною';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM "Store"."Stores" WHERE "Id" = p_store_id AND "IsDeleted" = false) THEN
        RAISE EXCEPTION 'Магазин % не знайдено', p_store_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM "Store"."Categories" WHERE "Id" = p_category_id AND "IsDeleted" = false) THEN
        RAISE EXCEPTION 'Категорію % не знайдено', p_category_id;
    END IF;
    INSERT INTO "Store"."Products" ("StoreId", "CategoryId", "Name", "Description", "Price")
    VALUES (p_store_id, p_category_id, p_name, p_description, p_price)
    RETURNING "Id" INTO p_id;
END $$;

-- P5. М'яко видалити товар (і прибрати його з кошиків)
CREATE OR REPLACE PROCEDURE "Store".sp_soft_delete_product(p_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE "Store"."Products" SET "IsDeleted" = true WHERE "Id" = p_id AND "IsDeleted" = false;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Товар % не знайдено або вже видалений', p_id;
    END IF;
    DELETE FROM "Store"."CartItems"
    WHERE "ProductSizeId" IN (SELECT "Id" FROM "Store"."ProductSizes" WHERE "ProductId" = p_id);
END $$;

-- P6. Відновити видалений товар
CREATE OR REPLACE PROCEDURE "Store".sp_restore_product(p_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE "Store"."Products" SET "IsDeleted" = false WHERE "Id" = p_id AND "IsDeleted" = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Видаленого товару % не знайдено', p_id;
    END IF;
END $$;

-- 5. ДОВІДНИКИ
INSERT INTO "Store"."Roles" ("Name") VALUES ('Admin'), ('Seller'), ('Customer') ON CONFLICT DO NOTHING;
INSERT INTO "Store"."Sizes" ("Name") VALUES ('XS'), ('S'), ('M'), ('L'), ('XL') ON CONFLICT DO NOTHING;

COMMIT;