using System.ComponentModel.DataAnnotations;

namespace ToeicApp.Users.Dto;

public class ChangeUserLanguageDto
{
    [Required]
    public string LanguageName { get; set; }
}