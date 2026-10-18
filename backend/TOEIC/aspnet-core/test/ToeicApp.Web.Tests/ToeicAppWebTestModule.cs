using Abp.AspNetCore;
using Abp.AspNetCore.TestBase;
using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicApp.EntityFrameworkCore;
using ToeicApp.Web.Startup;
using Microsoft.AspNetCore.Mvc.ApplicationParts;

namespace ToeicApp.Web.Tests;

[DependsOn(
    typeof(ToeicAppWebMvcModule),
    typeof(AbpAspNetCoreTestBaseModule)
)]
public class ToeicAppWebTestModule : AbpModule
{
    public ToeicAppWebTestModule(ToeicAppEntityFrameworkModule abpProjectNameEntityFrameworkModule)
    {
        abpProjectNameEntityFrameworkModule.SkipDbContextRegistration = true;
    }

    public override void PreInitialize()
    {
        Configuration.UnitOfWork.IsTransactional = false; //EF Core InMemory DB does not support transactions.
    }

    public override void Initialize()
    {
        IocManager.RegisterAssemblyByConvention(typeof(ToeicAppWebTestModule).GetAssembly());
    }

    public override void PostInitialize()
    {
        IocManager.Resolve<ApplicationPartManager>()
            .AddApplicationPartsIfNotAddedBefore(typeof(ToeicAppWebMvcModule).Assembly);
    }
}