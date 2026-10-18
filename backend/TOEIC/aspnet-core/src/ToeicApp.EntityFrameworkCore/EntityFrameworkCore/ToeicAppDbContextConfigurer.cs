using Microsoft.EntityFrameworkCore;
using System.Data.Common;

namespace ToeicApp.EntityFrameworkCore;

public static class ToeicAppDbContextConfigurer
{
    public static void Configure(DbContextOptionsBuilder<ToeicAppDbContext> builder, string connectionString)
    {
        builder.UseSqlServer(connectionString);
    }

    public static void Configure(DbContextOptionsBuilder<ToeicAppDbContext> builder, DbConnection connection)
    {
        builder.UseSqlServer(connection);
    }
}
