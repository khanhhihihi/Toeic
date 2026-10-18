using Abp.AspNetCore.Mvc.ViewComponents;

namespace ToeicApp.Web.Views;

public abstract class ToeicAppViewComponent : AbpViewComponent
{
    protected ToeicAppViewComponent()
    {
        LocalizationSourceName = ToeicAppConsts.LocalizationSourceName;
    }
}
