using MultiStoreApp.Models;

namespace MultiStoreApp.Repositories;

public interface IStoreRepository
{
    List<StoreInfo> GetActive();             // vw_active_stores
    List<StoreSales> GetSalesSummary();      // vw_store_sales_summary
    int Create(int ownerId, string name, string? description, string contactEmail); // sp_create_store
    void SoftDelete(int storeId);            // sp_soft_delete_store
}
