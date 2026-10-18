using ToeicApp.Roles.Dto;
using System.Collections.Generic;

namespace ToeicApp.Web.Models.Users;

public class UserListViewModel
{
    public IReadOnlyList<RoleDto> Roles { get; set; }
}
