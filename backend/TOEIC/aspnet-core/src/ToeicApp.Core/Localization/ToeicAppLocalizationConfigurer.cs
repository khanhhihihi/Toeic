using Abp.Configuration.Startup;
using Abp.Localization.Dictionaries;
using Abp.Localization.Dictionaries.Xml;
using Abp.Reflection.Extensions;

namespace ToeicApp.Localization;

public static class ToeicAppLocalizationConfigurer
{
    public static void Configure(ILocalizationConfiguration localizationConfiguration)
    {
        localizationConfiguration.Sources.Add(
            new DictionaryBasedLocalizationSource(ToeicAppConsts.LocalizationSourceName,
                new XmlEmbeddedFileLocalizationDictionaryProvider(
                    typeof(ToeicAppLocalizationConfigurer).GetAssembly(),
                    "ToeicApp.Localization.SourceFiles"
                )
            )
        );
    }
}
