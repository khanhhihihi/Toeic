using Abp.Authorization;
using Abp.Runtime.Session;
using ToeicApp.Configuration.Dto;
using System.Threading.Tasks;

namespace ToeicApp.Configuration;

[AbpAuthorize]
public class ConfigurationAppService : ToeicAppAppServiceBase, IConfigurationAppService
{
    public async Task ChangeUiTheme(ChangeUiThemeInput input)
    {
        await SettingManager.ChangeSettingForUserAsync(AbpSession.ToUserIdentifier(), AppSettingNames.UiTheme, input.Theme);
    }
}
