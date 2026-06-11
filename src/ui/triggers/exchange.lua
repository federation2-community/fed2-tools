-- @patterns:
--   - pattern: ^\+{3} The exchange display shows the prices for (.+) \+{3}
--     type: regex
--   - pattern: ^\+{3} The display shows the prices for (.+) \+{3}
--     type: regex
--   - pattern: ^\+{3} Exchange will buy \d+ tons at \d+.+ \+{3}
--     type: regex
--   - pattern: ^\+{3} Exchange has .+ for sale \+{3}
--     type: regex
--   - pattern: ^\+{3} Offer price is \d+.+ for first \d+ tons \+{3}
--     type: regex

-- Assemble multi-line exchange spam into single per-commodity ticker entries.
-- Each commodity announcement spans 2-4 lines; we accumulate into UI.exchange.ticker_inflight
-- and emit when the next commodity's header arrives, or after 0.5s of silence.

UI.exchange = UI.exchange or { ticker_inflight = nil, ticker_timer = nil, ticker_entries = {} }

local function _emit_inflight()
    local inf = UI.exchange.ticker_inflight
    if not inf then return end
    UI.exchange.ticker_inflight = nil
    if UI.exchange.ticker_timer then
        killTimer(UI.exchange.ticker_timer)
        UI.exchange.ticker_timer = nil
    end
    local mode = f2t_settings_get("ui", "exchange_ticker_mode") or "ticker"
    if mode == "ticker" or mode == "both" then
        ui_exchange_ticker_add(inf)
    end
end

local function _reset_timer()
    if UI.exchange.ticker_timer then killTimer(UI.exchange.ticker_timer) end
    UI.exchange.ticker_timer = tempTimer(0.5, function()
        UI.exchange.ticker_timer = nil
        _emit_inflight()
    end)
end

if line:match("shows the prices for") then
    -- New commodity header: emit the previous in-flight entry first.
    _emit_inflight()
    local name       = line:match("for (.+) %+%+%+")
    local base_price = nil
    if name then
        name = name:gsub("%s+$", "")  -- strip trailing whitespace
        local commodities = ui_commodities_load and ui_commodities_load() or {}
        for _, commodity in ipairs(commodities) do
            if commodity.name == name then base_price = commodity.basePrice; break end
        end
        UI.exchange.ticker_inflight = { name = name, base = base_price }
        _reset_timer()
    end

elseif line:match("Exchange will buy") then
    if UI.exchange.ticker_inflight then
        UI.exchange.ticker_inflight.buy = tonumber(line:match("at (%d+)"))
        _reset_timer()
    end

elseif line:match("Exchange has") then
    if UI.exchange.ticker_inflight then
        UI.exchange.ticker_inflight.sell_qty = line:match("has (.+) for sale")
        _reset_timer()
    end

elseif line:match("Offer price is") then
    if UI.exchange.ticker_inflight then
        UI.exchange.ticker_inflight.sell = tonumber(line:match("Offer price is (%d+)"))
        _reset_timer()
    end
end

-- In ticker-only mode, delete the exchange spam from the main console.
-- In console or both modes, let it show in the main output.
local _mode = f2t_settings_get("ui", "exchange_ticker_mode") or "ticker"
if _mode == "ticker" then
    tempLineTrigger(1, 1, function()
        if line == "" or line:match("^%s*$") then deleteLine() end
    end)
    deleteLine()
end
