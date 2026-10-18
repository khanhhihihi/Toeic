using ToeicApp.Configuration.Dto;
using System.Threading.Tasks;

namespace ToeicApp.Configuration;

public interface IConfigurationAppService
{
    Task ChangeUiTheme(ChangeUiThemeInput input);
}
