using Abp.AspNetCore.Mvc.Controllers;
using Abp.IdentityFramework;
using Microsoft.AspNetCore.Identity;

namespace ToeicApp.Controllers
{
    public abstract class ToeicAppControllerBase : AbpController
    {
        protected ToeicAppControllerBase()
        {
            LocalizationSourceName = ToeicAppConsts.LocalizationSourceName;
        }

        protected void CheckErrors(IdentityResult identityResult)
        {
            identityResult.CheckErrors(LocalizationManager);
        }
    }
}
