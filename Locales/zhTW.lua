local ns = select(2, ...)
if (ns.LOCALE or (GetLocale and GetLocale())) ~= "zhTW" then return end
local L = ns.L

-- Chinese (traditional): CurseForge's packager puts the translations from its localization tool where the keyword is (a release
-- built from a version tag: .github/workflows/release.yml). Untranslated texts stay English.
--@localization(locale="zhTW", format="lua_additive_table", handle-unlocalized="ignore")@
