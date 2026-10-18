using Abp.AspNetCore.Mvc.Authorization;
using ToeicApp.Controllers;
using Microsoft.AspNetCore.Mvc;

namespace ToeicApp.Web.Controllers;

[AbpMvcAuthorize]
public class AboutController : ToeicAppControllerBase
{
    public ActionResult Index()
    {
        return View();
    }
}
