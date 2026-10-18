using Abp.Events.Bus;
using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicApp.Configuration;
using ToeicApp.EntityFrameworkCore;
using ToeicApp.Migrator.DependencyInjection;
using Castle.MicroKernel.Registration;
using Microsoft.Extensions.Configuration;

namespace ToeicApp.Migrator;

[DependsOn(typeof(ToeicAppEntityFrameworkModule))]
public class ToeicAppMigratorModule : AbpModule
{
    private readonly IConfigurationRoot _appConfiguration;

    public ToeicAppMigratorModule(ToeicAppEntityFrameworkModule abpProjectNameEntityFrameworkModule)
    {
        abpProjectNameEntityFrameworkModule.SkipDbSeed = true;

        _appConfiguration = AppConfigurations.Get(
            typeof(ToeicAppMigratorModule).GetAssembly().GetDirectoryPathOrNull()
        );
    }

    public override void PreInitialize()
    {
        Configuration.DefaultNameOrConnectionString = _appConfiguration.GetConnectionString(
            ToeicAppConsts.ConnectionStringName
        );

        Configuration.BackgroundJobs.IsJobExecutionEnabled = false;
        Configuration.ReplaceService(
            typeof(IEventBus),
            () => IocManager.IocContainer.Register(
                Component.For<IEventBus>().Instance(NullEventBus.Instance)
            )
        );
    }

    public override void Initialize()
    {
        IocManager.RegisterAssemblyByConvention(typeof(ToeicAppMigratorModule).GetAssembly());
        ServiceCollectionRegistrar.Register(IocManager);
    }
}
