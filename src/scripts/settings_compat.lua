-- fed2-tools — settings compatibility layer
--
-- Bridges old f2t_settings_* API → Mux.settings so all ported map scripts
-- work without modification.
--
-- When Mux is not yet available (first run before Muxlet installs) calls are
-- queued and flushed by startWorkspace() in init.lua once Mux is ready.

local _registry = {}          -- {component → {key → config}}  (always maintained)
local _local_data = {}        -- fallback store when Mux unavailable
local _pending = {}           -- settings registrations queued before Mux loaded

-- ── f2t_settings proxy ───────────────────────────────────────────────────────
-- Scripts that access f2t_settings.map.destinations directly (destinations.lua)
-- resolve through this proxy to Mux.settings._data when available.
f2t_settings = setmetatable({}, {
    __index = function(_, component)
        local store = (Mux and Mux.settings and Mux.settings._data) or _local_data
        store[component] = store[component] or {}
        return store[component]
    end,
    __newindex = function(_, component, v)
        local store = (Mux and Mux.settings and Mux.settings._data) or _local_data
        store[component] = v
    end,
})

-- ── Persistence ───────────────────────────────────────────────────────────────

function f2t_save_settings()
    if Mux and Mux.settings and Mux.settings.save then
        Mux.settings.save()
    end
end

function f2t_load_settings()
    if Mux and Mux.settings and Mux.settings.load then
        Mux.settings.load()
    end
end

-- ── Registration ─────────────────────────────────────────────────────────────

function f2t_settings_register(component, key, config)
    -- Always keep a local copy for fallback get() calls.
    _registry[component] = _registry[component] or {}
    _registry[component][key] = config

    if Mux and Mux.settings and Mux.settings.register then
        Mux.settings.register(component, key, {
            description = config.description,
            default     = config.default,
            choices     = config.choices,
            min         = config.min,
            max         = config.max,
        })
    else
        table.insert(_pending, {component = component, key = key, config = config})
    end
end

-- Flush queued registrations — called from init.lua's startWorkspace() after Mux loads.
function f2t_settings_flush_registrations()
    if not (Mux and Mux.settings and Mux.settings.register) then return end
    for _, reg in ipairs(_pending) do
        Mux.settings.register(reg.component, reg.key, {
            description = reg.config.description,
            default     = reg.config.default,
            choices     = reg.config.choices,
            min         = reg.config.min,
            max         = reg.config.max,
        })
    end
    _pending = {}
end

-- ── Access ────────────────────────────────────────────────────────────────────

function f2t_settings_get(component, key)
    if Mux and Mux.settings and Mux.settings.get then
        return Mux.settings.get(component, key)
    end
    local store = _local_data[component] or {}
    local v = store[key]
    if v ~= nil then return v end
    local reg = _registry[component] and _registry[component][key]
    return reg and reg.default or nil
end

function f2t_settings_set(component, key, value)
    if Mux and Mux.settings and Mux.settings.set then
        return Mux.settings.set(component, key, value)
    end
    _local_data[component] = _local_data[component] or {}
    _local_data[component][key] = value
    return true
end

function f2t_settings_clear(component, key)
    if Mux and Mux.settings and Mux.settings.clear then
        return Mux.settings.clear(component, key)
    end
    _local_data[component] = _local_data[component] or {}
    _local_data[component][key] = nil
    return true
end

-- ── Display / command helpers ─────────────────────────────────────────────────

function f2t_handle_settings_command(component, args_str)
    if Mux and Mux.settings and Mux.settings.handleCommand then
        return Mux.settings.handleCommand(component, args_str)
    end
    cecho(string.format("\n<yellow>[%s]<reset> Settings system not yet available\n", component))
end

function f2t_settings_show_list(component)
    if Mux and Mux.settings and Mux.settings.showList then
        Mux.settings.showList(component)
    end
end

function f2t_settings_show_get(component, key)
    if Mux and Mux.settings and Mux.settings.showSetting then
        Mux.settings.showSetting(component, key)
    end
end
