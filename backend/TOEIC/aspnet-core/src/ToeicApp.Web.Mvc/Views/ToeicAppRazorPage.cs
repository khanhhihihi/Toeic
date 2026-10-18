using Abp.AspNetCore.Mvc.Views;
using Abp.Runtime.Session;
using Microsoft.AspNetCore.Mvc.Razor.Internal;

namespace ToeicApp.Web.Views;

public abstract class ToeicAppRazorPage<TModel> : AbpRazorPage<TModel>
{
    [RazorInject]
    public IAbpSession AbpSession { get; set; }

    protected ToeicAppRazorPage()
    {
        LocalizationSourceName = ToeicAppConsts.LocalizationSourceName;
    }
}
