using MultiStoreApp.Data;

const string cs = "Host=localhost;Port=5432;Database=ecommerce_db;Username=postgres;Password=dasha2007";
const int sellerId = 1; 
const int categoryId = 1;

// Унікальна назва, щоб програму можна було запускати повторно 
string storeName = "Urban Style " + DateTime.Now.ToString("HHmmss");

int storeId, productId;

// 1. Одна транзакція: магазин + два товари (логічно пов'язані сутності)
using (IUnitOfWork uow = new UnitOfWork(cs, sellerId))
{
    storeId = uow.Stores.Create(sellerId, storeName, "Одяг та взуття", "shop@urban.test");
    productId = uow.Products.Create(storeId, categoryId, "Футболка", "Бавовняна футболка", 499.00m);
    uow.Products.Create(storeId, categoryId, "Худі", "Тепле худі", 1299.00m);
    uow.Commit();
    Console.WriteLine($"1) Створено магазин {storeId} і товари (транзакцію зафіксовано)");
}

// 2. Читання через подання
using (IUnitOfWork uow = new UnitOfWork(cs, sellerId))
{
    Console.WriteLine("\n2) Каталог (vw_active_products):");
    foreach (var p in uow.Products.GetCatalog(storeId))
        Console.WriteLine($"   #{p.ProductId} {p.ProductName} | {p.Price} грн | {p.StoreName} | {p.CategoryName} | рейтинг {p.AvgRating}");

    Console.WriteLine("   Продажі (vw_store_sales_summary):");
    foreach (var s in uow.Stores.GetSalesSummary())
        Console.WriteLine($"   {s.StoreName}: замовлень {s.OrdersCount}, виручка {s.Revenue}");
}

// 3. Soft delete і відновлення товару
using (IUnitOfWork uow = new UnitOfWork(cs, sellerId))
{
    uow.Products.SoftDelete(productId);
    uow.Commit();
}
using (IUnitOfWork uow = new UnitOfWork(cs, sellerId))
{
    Console.WriteLine("\n3) Після soft delete:");
    Console.WriteLine($"   у каталозі: {uow.Products.GetCatalog(storeId).Count} товар(ів)");
    foreach (var d in uow.Products.GetDeleted())
        Console.WriteLine($"   у кошику: #{d.ProductId} {d.ProductName}, видалив користувач {d.DeletedBy}, {d.DeletedAt}");

    uow.Products.Restore(productId);
    uow.Commit();
    Console.WriteLine("   товар відновлено");
}

// 4. Відкат: помилка в другому кроці скасовує і перший
try
{
    using IUnitOfWork uow = new UnitOfWork(cs, sellerId);
    uow.Stores.Create(sellerId, "Temp Store", null, "temp@test");
    uow.Products.Create(storeId, categoryId, "Брак", "Від'ємна ціна", -5m);
    uow.Commit();
}
catch (Exception ex)
{
    Console.WriteLine($"\n4) Помилка: {ex.Message}");
}
using (IUnitOfWork uow = new UnitOfWork(cs, sellerId))
{
    bool exists = uow.Stores.GetActive().Any(s => s.Name == "Temp Store");
    Console.WriteLine($"   Магазин 'Temp Store' існує? {exists} (транзакцію відкочено)");
}