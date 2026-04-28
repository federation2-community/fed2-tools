-- =============================================================================
-- ui_adaptive — Two-stage adaptive display for narrow windows
--
-- Stage 1: Scale font from MAX_FONT down to MIN_FONT as the frame shrinks.
-- Stage 2: If MIN_FONT still doesn't fit, expand the frame from MIN_FRAME %
--          toward MAX_FRAME %. Beyond that, layout degrades naturally.
--
-- Public API:
--   ui_adaptive_fit()       — full fit (font + frame); call on window resize
--   ui_adaptive_font_only() — font only (no frame move); call on panel drag
-- =============================================================================

local CHAR_RATIO = 0.60   -- monospace char width ≈ font_size × this value
local MAX_FONT   = 12     -- design-intent font size; never upscale past this
local MIN_FONT   = 8      -- minimum readable size before giving up
local MIN_FRAME  = 20     -- natural frame width (%)
local MAX_FRAME  = 30     -- adaptive expansion ceiling (%)

-- Maps each frame side to the table IDs that live inside it.
-- Update this if new tables are added to the left or right panels.
local FRAME_TABLES = {
    left  = { "who_list" },
    right = { "hauling_jobs", "trading_data" },
}

local _busy = false  -- re-entry guard: prevents fit-triggered repositions from looping

-- =============================================================================
-- Helpers
-- =============================================================================

-- Sum all column character widths + between-column separators for a table.
local function table_char_width(table_id)
    local tbl = UI.tables and UI.tables[table_id]
    if not tbl then return 0 end
    local total = 0
    local n     = #tbl.columns
    for i, col in ipairs(tbl.columns) do
        total = total + (col.width or 0)
        if i < n then
            local sep = col.separator or (tbl.separators and tbl.separators.column) or " "
            total = total + #sep
        end
    end
    return total
end

-- Worst-case (widest) table on a given side.
local function needed_chars(side)
    local worst = 0
    for _, tid in ipairs(FRAME_TABLES[side] or {}) do
        local w = table_char_width(tid)
        if w > worst then worst = w end
    end
    return worst
end

local function get_frame(side)
    return (side == "left") and UI.left_frame or UI.right_frame
end

-- Apply font to every miniconsole on a side.
-- Skips setFontSize + re-render when the font hasn't changed.
local function apply_font(side, font_size)
    for _, tid in ipairs(FRAME_TABLES[side] or {}) do
        local tbl = UI.tables and UI.tables[tid]
        if tbl and tbl.window and tbl._adaptive_font ~= font_size then
            tbl._adaptive_font = font_size
            tbl.window:setFontSize(font_size)
            if tbl.data and #tbl.data > 0 then
                ui_table_render(tid)
            end
        end
    end
end

-- =============================================================================
-- Fit computation
-- =============================================================================

-- Compute the optimal (frame_pct, font_size) pair for a side.
-- Frame pct is anchored to MIN_FRAME when font scaling alone suffices;
-- it expands toward MAX_FRAME only when MIN_FONT still can't fit the columns.
local function compute_fit(side)
    local chars    = needed_chars(side)
    local screen_w = getMainWindowSize()

    if chars == 0 or screen_w <= 0 then
        return MIN_FRAME, MAX_FONT
    end

    -- How many pixels would the frame have at its natural width?
    local natural_px = screen_w * MIN_FRAME / 100
    local raw_font   = natural_px / (chars * CHAR_RATIO)

    if raw_font >= MIN_FONT then
        -- Font scaling alone is sufficient; keep frame at natural width.
        local font = math.max(MIN_FONT, math.min(MAX_FONT, math.floor(raw_font)))
        return MIN_FRAME, font
    end

    -- MIN_FONT doesn't fit at MIN_FRAME — expand the frame.
    local needed_px  = chars * MIN_FONT * CHAR_RATIO
    local needed_pct = (needed_px / screen_w) * 100
    local frame_pct  = math.min(MAX_FRAME, math.max(MIN_FRAME, needed_pct))

    return frame_pct, MIN_FONT
end

-- =============================================================================
-- Public API
-- =============================================================================

-- Full adaptive fit: adjusts frame widths AND font sizes.
-- Wire to sysWindowResizeEvent and the post-build timer.
function ui_adaptive_fit()
    if _busy then return end
    _busy = true

    local screen_w = getMainWindowSize()

    for _, side in ipairs({ "left", "right" }) do
        local frame = get_frame(side)
        if frame and screen_w > 0 then
            local target_pct, target_font = compute_fit(side)
            local cur_pct = (frame:get_width() / screen_w) * 100

            if math.abs(target_pct - cur_pct) > 0.5 then
                frame:resize(target_pct .. "%", nil)
                local frame_name = (side == "left") and "UI.left_frame" or "UI.right_frame"
                ui_on_container_reposition(nil, frame_name)
            end

            apply_font(side, target_font)
        end
    end

    _busy = false
end

-- Font-only fit: adjusts fonts based on the current frame widths, no frame moves.
-- Wire to AdjustableContainerRepositionFinish so user-dragged panel borders
-- still cause font to scale without fighting the user's resize choice.
function ui_adaptive_font_only()
    if _busy then return end

    for _, side in ipairs({ "left", "right" }) do
        local frame = get_frame(side)
        if frame then
            local chars    = needed_chars(side)
            local frame_px = frame:get_width()
            if chars > 0 and frame_px > 0 then
                local raw_font    = frame_px / (chars * CHAR_RATIO)
                local target_font = math.max(MIN_FONT, math.min(MAX_FONT, math.floor(raw_font)))
                apply_font(side, target_font)
            end
        end
    end
end
