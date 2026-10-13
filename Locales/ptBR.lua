local ns = select(2, ...)
if (ns.LOCALE or (GetLocale and GetLocale())) ~= "ptBR" then return end
local L = ns.L

-- Portuguese (Brazil): CurseForge's packager puts the translations from its localization tool where the keyword is (a release
-- built from a version tag: .github/workflows/release.yml). Untranslated texts stay English.
--@localization(locale="ptBR", format="lua_additive_table", handle-unlocalized="ignore")@
