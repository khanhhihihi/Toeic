using Abp.Authorization;
using ToeicApp.Authorization.Roles;
using ToeicApp.Authorization.Users;

namespace ToeicApp.Authorization;

public class PermissionChecker : PermissionChecker<Role, User>
{
    public PermissionChecker(UserManager userManager)
        : base(userManager)
    {
    }
}
