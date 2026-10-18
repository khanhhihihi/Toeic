using ToeicApp.Roles.Dto;
using System.Collections.Generic;

namespace ToeicApp.Web.Models.Common;

public interface IPermissionsEditViewModel
{
    List<FlatPermissionDto> Permissions { get; set; }
}