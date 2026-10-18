using ToeicApp.Roles.Dto;
using System.Collections.Generic;

namespace ToeicApp.Web.Models.Roles;

public class RoleListViewModel
{
    public IReadOnlyList<PermissionDto> Permissions { get; set; }
}
