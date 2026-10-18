using Abp.Zero.EntityFrameworkCore;
using ToeicApp.Authorization.Roles;
using ToeicApp.Authorization.Users;
using ToeicApp.MultiTenancy;
using Microsoft.EntityFrameworkCore;

namespace ToeicApp.EntityFrameworkCore;

public class ToeicAppDbContext : AbpZeroDbContext<Tenant, Role, User, ToeicAppDbContext>
{
    /* Define a DbSet for each entity of the application */

    public ToeicAppDbContext(DbContextOptions<ToeicAppDbContext> options)
        : base(options)
    {
    }
}
