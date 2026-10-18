using Abp.Application.Services;
using ToeicApp.Authorization.Accounts.Dto;
using System.Threading.Tasks;

namespace ToeicApp.Authorization.Accounts;

public interface IAccountAppService : IApplicationService
{
    Task<IsTenantAvailableOutput> IsTenantAvailable(IsTenantAvailableInput input);

    Task<RegisterOutput> Register(RegisterInput input);
}
