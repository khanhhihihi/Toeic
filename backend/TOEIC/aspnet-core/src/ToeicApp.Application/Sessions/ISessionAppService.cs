using Abp.Application.Services;
using ToeicApp.Sessions.Dto;
using System.Threading.Tasks;

namespace ToeicApp.Sessions;

public interface ISessionAppService : IApplicationService
{
    Task<GetCurrentLoginInformationsOutput> GetCurrentLoginInformations();
}
