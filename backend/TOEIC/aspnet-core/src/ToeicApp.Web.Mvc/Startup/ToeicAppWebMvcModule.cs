using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicApp.Configuration;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace ToeicApp.Web.Startup;

[DependsOn(typeof(ToeicAppWebCoreModule))]
public class ToeicAppWebMvcModule : AbpModule
{
    private readonly IWebHostEnvironment _env;
    private readonly IConfigurationRoot _appConfiguration;

    public ToeicAppWebMvcModule(IWebHostEnvironment env)
    {
        _env = env;
        _appConfiguration = env.GetAppConfiguration();
    }

    public override void PreInitialize()
    {
        Configuration.Navigation.Providers.Add<ToeicAppNavigationProvider>();
    }

    public override void Initialize()
    {
        IocManager.RegisterAssemblyByConvention(typeof(ToeicAppWebMvcModule).GetAssembly());
    }
}
