using MultiStoreApp.Repositories;
using Npgsql;

namespace MultiStoreApp.Data;

public class UnitOfWork : IUnitOfWork
{
    private readonly NpgsqlConnection _conn;
    private readonly NpgsqlTransaction _tx;
    private bool _finished;

    public IStoreRepository Stores { get; }
    public IProductRepository Products { get; }

    public UnitOfWork(string connectionString, int currentUserId)
    {
        _conn = new NpgsqlConnection(connectionString);
        _conn.Open();
        _tx = _conn.BeginTransaction();

        using (var cmd = new NpgsqlCommand(@"CALL ""Store"".sp_set_current_user(@id)", _conn, _tx))
        {
            cmd.Parameters.AddWithValue("id", currentUserId);
            cmd.ExecuteNonQuery();
        }

        Stores = new StoreRepository(_conn, _tx);
        Products = new ProductRepository(_conn, _tx);
    }

    public void Commit()
    {
        _tx.Commit();
        _finished = true;
    }

    public void Rollback()
    {
        _tx.Rollback();
        _finished = true;
    }

    public void Dispose()
    {
        if (!_finished) _tx.Rollback();
        _tx.Dispose();
        _conn.Dispose();
    }
}
