Locales = {}

function _U(str, ...)
    local translations = Locales[Config.Locale] or Locales['en'] or {}
    local translated = translations[str]
    if not translated then return str end

    if select('#', ...) > 0 then
        return string.format(translated, ...)
    end

    return translated
end
