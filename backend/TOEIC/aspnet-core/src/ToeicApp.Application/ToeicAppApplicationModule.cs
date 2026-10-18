using Abp.AutoMapper;
using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicApp.Authorization;

namespace ToeicApp;

[DependsOn(
    typeof(ToeicAppCoreModule),
    typeof(AbpAutoMapperModule))]
public class ToeicAppApplicationModule : AbpModule
{
    public override void PreInitialize()
    {
        Configuration.Authorization.Providers.Add<ToeicAppAuthorizationProvider>();
    }

    public override void Initialize()
    {
        var thisAssembly = typeof(ToeicAppApplicationModule).GetAssembly();

        IocManager.RegisterAssemblyByConvention(thisAssembly);

        Configuration.Modules.AbpAutoMapper().Configurators.Add(
            // Scan the assembly for classes which inherit from AutoMapper.Profile
            cfg => cfg.AddMaps(thisAssembly)
        );
    }
}
