using MultiStoreApp.Models;
using Npgsql;
using NpgsqlTypes;

namespace MultiStoreApp.Repositories;

public class ProductRepository : IProductRepository
{
    private readonly NpgsqlConnection _conn;
    private readonly NpgsqlTransaction _tx;

    public ProductRepository(NpgsqlConnection conn, NpgsqlTransaction tx)
    {
        _conn = conn;
        _tx = tx;
    }

    public List<ProductInfo> GetCatalog(int? storeId = null)
    {
        using var cmd = new NpgsqlCommand(
            @"SELECT product_id, product_name, description, price, store_id, store_name,
                     category_id, category_name, avg_rating, review_count, total_stock
              FROM ""Store"".vw_active_products
              WHERE (@store::integer IS NULL OR store_id = @store::integer)
              ORDER BY product_id", _conn, _tx);
        cmd.Parameters.Add(new NpgsqlParameter("store", NpgsqlDbType.Integer) { Value = (object?)storeId ?? DBNull.Value });
        using var r = cmd.ExecuteReader();
        var list = new List<ProductInfo>();
        while (r.Read())
            list.Add(new ProductInfo(r.GetInt32(0), r.GetString(1), r.GetString(2), r.GetDecimal(3),
                                     r.GetInt32(4), r.GetString(5), r.GetInt32(6), r.GetString(7),
                                     r.GetDecimal(8), r.GetInt64(9), r.GetInt64(10)));
        return list;
    }

    public List<DeletedProductInfo> GetDeleted()
    {
        using var cmd = new NpgsqlCommand(
            @"SELECT product_id, product_name, store_id, store_name, deleted_at, deleted_by
              FROM ""Store"".vw_deleted_products ORDER BY product_id", _conn, _tx);
        using var r = cmd.ExecuteReader();
        var list = new List<DeletedProductInfo>();
        while (r.Read())
            list.Add(new DeletedProductInfo(r.GetInt32(0), r.GetString(1), r.GetInt32(2), r.GetString(3),
                                            r.IsDBNull(4) ? null : r.GetDateTime(4),
                                            r.IsDBNull(5) ? null : r.GetInt32(5)));
        return list;
    }

    public int Create(int storeId, int categoryId, string name, string description, decimal price)
    {
        using var cmd = new NpgsqlCommand(
            @"CALL ""Store"".sp_create_product(@store, @cat, @name, @desc, @price, NULL)", _conn, _tx);
        cmd.Parameters.AddWithValue("store", storeId);
        cmd.Parameters.AddWithValue("cat", categoryId);
        cmd.Parameters.AddWithValue("name", name);
        cmd.Parameters.AddWithValue("desc", description);
        cmd.Parameters.AddWithValue("price", price);
        return (int)cmd.ExecuteScalar()!;
    }

    public void SoftDelete(int productId) => CallWithId("sp_soft_delete_product", productId);

    public void Restore(int productId) => CallWithId("sp_restore_product", productId);

    private void CallWithId(string procedure, int id)
    {
        using var cmd = new NpgsqlCommand($@"CALL ""Store"".{procedure}(@id)", _conn, _tx);
        cmd.Parameters.AddWithValue("id", id);
        cmd.ExecuteNonQuery();
    }
}
