using MultiStoreApp.Models;
using Npgsql;
using NpgsqlTypes;

namespace MultiStoreApp.Repositories;

public class StoreRepository : IStoreRepository
{
    private readonly NpgsqlConnection _conn;
    private readonly NpgsqlTransaction _tx;

    public StoreRepository(NpgsqlConnection conn, NpgsqlTransaction tx)
    {
        _conn = conn;
        _tx = tx;
    }

    public List<StoreInfo> GetActive()
    {
        using var cmd = new NpgsqlCommand(
            @"SELECT store_id, owner_id, name, description, contact_email, created_at
              FROM ""Store"".vw_active_stores ORDER BY store_id", _conn, _tx);
        using var r = cmd.ExecuteReader();
        var list = new List<StoreInfo>();
        while (r.Read())
            list.Add(new StoreInfo(r.GetInt32(0), r.GetInt32(1), r.GetString(2),
                                   r.IsDBNull(3) ? null : r.GetString(3),
                                   r.GetString(4), r.GetDateTime(5)));
        return list;
    }

    public List<StoreSales> GetSalesSummary()
    {
        using var cmd = new NpgsqlCommand(
            @"SELECT store_id, store_name, orders_count, revenue
              FROM ""Store"".vw_store_sales_summary ORDER BY store_id", _conn, _tx);
        using var r = cmd.ExecuteReader();
        var list = new List<StoreSales>();
        while (r.Read())
            list.Add(new StoreSales(r.GetInt32(0), r.GetString(1), r.GetInt64(2), r.GetDecimal(3)));
        return list;
    }

    public int Create(int ownerId, string name, string? description, string contactEmail)
    {
        using var cmd = new NpgsqlCommand(
            @"CALL ""Store"".sp_create_store(@owner, @name, @desc, @email, NULL)", _conn, _tx);
        cmd.Parameters.AddWithValue("owner", ownerId);
        cmd.Parameters.AddWithValue("name", name);
        cmd.Parameters.Add(new NpgsqlParameter("desc", NpgsqlDbType.Text) { Value = (object?)description ?? DBNull.Value });
        cmd.Parameters.AddWithValue("email", contactEmail);
        return (int)cmd.ExecuteScalar()!;
    }

    public void SoftDelete(int storeId)
    {
        using var cmd = new NpgsqlCommand(@"CALL ""Store"".sp_soft_delete_store(@id)", _conn, _tx);
        cmd.Parameters.AddWithValue("id", storeId);
        cmd.ExecuteNonQuery();
    }
}
