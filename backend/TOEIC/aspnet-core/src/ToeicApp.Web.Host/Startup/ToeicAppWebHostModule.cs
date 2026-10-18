using Abp.Modules;
using Abp.Reflection.Extensions;
using ToeicApp.Configuration;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace ToeicApp.Web.Host.Startup
{
    [DependsOn(
       typeof(ToeicAppWebCoreModule))]
    public class ToeicAppWebHostModule : AbpModule
    {
        private readonly IWebHostEnvironment _env;
        private readonly IConfigurationRoot _appConfiguration;

        public ToeicAppWebHostModule(IWebHostEnvironment env)
        {
            _env = env;
            _appConfiguration = env.GetAppConfiguration();
        }

        public override void Initialize()
        {
            IocManager.RegisterAssemblyByConvention(typeof(ToeicAppWebHostModule).GetAssembly());
        }
    }
}
