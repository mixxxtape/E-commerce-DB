using MultiStoreApp.Repositories;

namespace MultiStoreApp.Data;

public interface IUnitOfWork : IDisposable
{
    IStoreRepository Stores { get; }
    IProductRepository Products { get; }
    void Commit();
    void Rollback();
}
