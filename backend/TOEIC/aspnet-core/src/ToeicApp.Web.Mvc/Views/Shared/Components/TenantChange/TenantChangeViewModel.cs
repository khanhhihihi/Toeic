using Abp.AutoMapper;
using ToeicApp.Sessions.Dto;

namespace ToeicApp.Web.Views.Shared.Components.TenantChange;

[AutoMapFrom(typeof(GetCurrentLoginInformationsOutput))]
public class TenantChangeViewModel
{
    public TenantLoginInfoDto Tenant { get; set; }
}
