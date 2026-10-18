using Abp.Application.Services.Dto;
using Abp.AspNetCore.Mvc.Authorization;
using ToeicApp.Authorization;
using ToeicApp.Controllers;
using ToeicApp.MultiTenancy;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;

namespace ToeicApp.Web.Controllers;

[AbpMvcAuthorize(PermissionNames.Pages_Tenants)]
public class TenantsController : ToeicAppControllerBase
{
    private readonly ITenantAppService _tenantAppService;

    public TenantsController(ITenantAppService tenantAppService)
    {
        _tenantAppService = tenantAppService;
    }

    public ActionResult Index() => View();

    public async Task<ActionResult> EditModal(int tenantId)
    {
        var tenantDto = await _tenantAppService.GetAsync(new EntityDto(tenantId));
        return PartialView("_EditModal", tenantDto);
    }
}
