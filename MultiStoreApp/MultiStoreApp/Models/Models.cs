namespace MultiStoreApp.Models;

// Рядок з подання vw_active_stores
public record StoreInfo(int StoreId, int OwnerId, string Name, string? Description,
                        string ContactEmail, DateTime CreatedAt);

// Рядок з подання vw_store_sales_summary
public record StoreSales(int StoreId, string StoreName, long OrdersCount, decimal Revenue);

// Рядок з подання vw_active_products (каталог)
public record ProductInfo(int ProductId, string ProductName, string Description, decimal Price,
                          int StoreId, string StoreName, int CategoryId, string CategoryName,
                          decimal AvgRating, long ReviewCount, long TotalStock);

// Рядок з подання vw_deleted_products («кошик» адміністратора)
public record DeletedProductInfo(int ProductId, string ProductName, int StoreId, string StoreName,
                                 DateTime? DeletedAt, int? DeletedBy);
