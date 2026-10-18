using Abp.Application.Services;
using ToeicApp.MultiTenancy.Dto;

namespace ToeicApp.MultiTenancy;

public interface ITenantAppService : IAsyncCrudAppService<TenantDto, int, PagedTenantResultRequestDto, CreateTenantDto, TenantDto>
{
}

