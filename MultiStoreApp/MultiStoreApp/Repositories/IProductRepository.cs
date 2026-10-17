using MultiStoreApp.Models;

namespace MultiStoreApp.Repositories;

public interface IProductRepository
{
    List<ProductInfo> GetCatalog(int? storeId = null);  // vw_active_products
    List<DeletedProductInfo> GetDeleted();              // vw_deleted_products
    int Create(int storeId, int categoryId, string name, string description, decimal price); // sp_create_product
    void SoftDelete(int productId);                     // sp_soft_delete_product
    void Restore(int productId);                        // sp_restore_product
}
