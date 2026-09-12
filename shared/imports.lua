FeatherCore = FeatherCore or {}
FeatherCore.Locale = FeatherCore.Locale or {
    register = function(locale, translations)
        return exports['feather-core']:RegisterLocale(locale, translations)
    end,
    translate = function(source, key, ...)
        local result = exports['feather-core']:TranslateLocale(source or 0, key, ...)
        return type(result) == 'table' and result.ok == true and result.value
            or ('Translation [%s] is unavailable'):format(tostring(key))
    end
}
