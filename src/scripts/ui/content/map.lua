-- fed2-tools — Map content registration
--
-- Registers the Fed2 Map content with Muxlet: apply/remove lifecycle hooks that
-- mount and unmount a Geyser.Mapper widget inside a Muxlet pane.
--
-- Why the mapper needs special handling
-- -------------------------------------
-- Muxlet tears down content by deleting the disposable Geyser.Container slot it
-- wraps each apply() in; that delete is recursive, so for ordinary widgets no
-- remove() cleanup is needed.  A Geyser.Mapper is the exception on two counts:
--   1. The Mudlet map widget it wraps is NOT a true Qt child of its container,
--      so deleting the slot does not remove it (it would keep painting over
--      whatever replaced it), and Mudlet exposes no deleteMapper().
--   2. The native map is a GL surface that does NOT survive being reparented:
--      reparenting it into a new slot (or hiding then re-showing it) leaves it
--      blank, and updateMap()/show() do not revive it.
--
-- So a single mapper cannot simply be moved between slots.  Instead we CREATE A
-- FRESH mapper on every acquire (a fresh createMapper always renders), and PARK
-- the previous one — hidden, in a persistent off-view garage container — on
-- release.  Parked mappers are inert and invisible; they are kept referenced so
-- they are never garbage-orphaned over live content.  (Mudlet has no deleteMapper,
-- so a small number of parked widgets is the cost of reliable rendering; map
-- content is normally placed once, not toggled in a hot loop.)
--
-- f2tRegisterMapContent() is called from init.lua's muxletReady handler.

-- ── Mapper management ───────────────────────────────────────────────────────────
local liveMapper  = nil    -- the mapper currently shown in a pane (or nil)
local parked      = {}     -- previous mappers, hidden in the garage
local mapperGarage = nil
local mapperSeq   = 0

-- Slot container + gid of the currently live map pane, so code outside this
-- apply() closure (settings gear menu, "map import db" alias) can build the
-- import overlay into the right place. See f2tGetMapSlotInfo() below.
local liveSlotContent = nil
local liveGid         = nil

-- Persistent, hidden, full-size holder that parked mappers live in so they are
-- never orphaned inside a deleted content slot.
local function ensureGarage()
    if mapperGarage then return mapperGarage end
    mapperGarage = Geyser.Container:new({
        name   = "f2t_mapper_garage",
        x      = 0, y = 0, width = "100%", height = "100%",
    })
    pcall(function() mapperGarage:hide() end)
    return mapperGarage
end

-- Move the current live mapper into the hidden garage (and remember it).
local function parkLive()
    if not liveMapper then return end
    ensureGarage()
    local m = liveMapper
    liveMapper = nil
    pcall(function() m:hide() end)
    pcall(function() m:changeContainer(mapperGarage) end)
    parked[#parked + 1] = m
end

-- Acquire a mapper into `slotContent`.  Always a FRESH widget (reparenting an
-- existing one renders blank), with the prior one parked first.
local function mapperAcquire(slotContent)
    ensureGarage()
    parkLive()
    mapperSeq = mapperSeq + 1
    liveMapper = Geyser.Mapper:new({
        name   = "f2t_mapper_" .. mapperSeq,
        x      = "0%", y = "0%",
        width  = "100%", height = "100%",
    }, slotContent)
    pcall(function()
        liveMapper:show()
        liveMapper:reposition()
    end)
    if updateMap then pcall(updateMap) end
    return liveMapper
end

-- Park the live mapper on content removal, BEFORE the slot is destroyed, so it is
-- never orphaned in a deleted container nor left drawing over the replacement.
local function mapperRelease()
    parkLive()
end

-- Refit the live mapper to the current slot (called from resize()).
local function mapperFit()
    if not liveMapper then return end
    pcall(function()
        liveMapper:move("0%", "0%")
        liveMapper:resize("100%", "100%")
        liveMapper:reposition()
    end)
    if updateMap then pcall(updateMap) end
end

local function buildContentDef()
    -- Token-based guard: each apply mints a new token table.  The deferred timer
    -- checks this token before building; remove() clears it so a timer that fires
    -- after removal is a no-op (prevents an orphaned mapper on rapid apply→remove).
    local activeToken = nil

    return {
        name        = "Fed2 Map",
        description = "Federation 2 mapper",
        group       = "Fed2 Tools",
        singleton   = true,

        apply = function(target)
            target.contentBg:echo("")
            target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
            target.contentBg:hide()

            local gid = target._gid

            -- target.content points to the framework's slot container right now
            -- (during apply).  After this function returns, the framework restores
            -- target.content to the real pane container, so the deferred callback
            -- must capture the slot reference here before returning.
            local slotContent = target.content

            local myToken = {}
            activeToken = myToken

            tempTimer(0.1, function()
                if activeToken ~= myToken then return end

                -- Build the mapper + overlays under pcall so a failure here can
                -- never swallow the import-check scheduling below.
                local ok, err = pcall(function()
                    local mapper = mapperAcquire(slotContent)
                    target._f2tHasMapper = true
                    liveSlotContent, liveGid = slotContent, gid
                    if mapper then mapper:raise() end

                    -- Mudlet's own mapper widget shows a built-in "No map yet
                    -- for this profile" empty-state overlay whenever the room
                    -- database is empty, with its own raw Load/Create buttons
                    -- — entirely outside fed2-tools' control, no Lua hook to
                    -- suppress it. This is UNRELATED to the show_import_prompt
                    -- decision below: it just seeds the player's current room
                    -- from already-cached GMCP data (no command sent to the
                    -- game) whenever the database happens to be empty, purely
                    -- so that native overlay never gets a chance to stick —
                    -- fed2-tools decides what the user sees here, never raw
                    -- Mudlet. See map/import_check.lua for the prompt decision
                    -- itself, which never looks at room count.
                    if next(getRooms()) == nil and type(f2t_map_handle_gmcp_room) == "function" then
                        f2t_map_handle_gmcp_room()
                    end

                    -- Movement button overlay lives on top of the mapper.  It is
                    -- a true child of the slot, so the framework's slot delete
                    -- removes it cleanly on content change/removal.
                    if f2tBuildMapMovement then
                        local mvShell = f2tBuildMapMovement(slotContent, gid)
                        if mvShell then mvShell:raise() end
                    end

                    -- Settings gear (manual import/export) — top of the stack.
                    if f2tBuildMapSettings then
                        local setShell = f2tBuildMapSettings(slotContent, gid)
                        if setShell then setShell:raise() end
                    end
                end)
                if not ok then
                    f2t_debug_log("[map content] overlay build error: %s", tostring(err))
                end

                -- Offer the bundled map-database import overlay on first load /
                -- after an upgrade (decision lives entirely in f2tCheckMapImport's
                -- persisted show_import_prompt setting — see map/import_check.lua;
                -- it never looks at room count). Built directly into this slot
                -- (not a separate floating dialog) so it stacks above the native
                -- mapper widget exactly like the overlays above.
                if f2tCheckMapImport then
                    f2tCheckMapImport()
                else
                    f2t_debug_log("[map content] f2tCheckMapImport missing — cannot offer import")
                end
            end)
        end,

        -- Detach the shared mapper into the hidden garage BEFORE the framework
        -- deletes the slot, so it is never orphaned inside a deleted container and
        -- never keeps drawing over whatever content replaces it.  The movement /
        -- settings overlays are real slot children and are removed by the slot
        -- delete automatically.
        remove = function(target)
            activeToken = nil
            mapperRelease()
            target._f2tHasMapper = nil
            liveSlotContent, liveGid = nil, nil
        end,

        -- Keep the mapper filling the slot as the pane/tab is resized.
        resize = function(target)
            if target._f2tHasMapper then mapperFit() end
        end,
    }
end

-- Lets code outside this apply() closure (settings gear menu, "map import db"
-- alias) build the import overlay into the live map pane's slot. Returns
-- nil, nil if no Fed2 Map content is currently applied anywhere.
function f2tGetMapSlotInfo()
    return liveSlotContent, liveGid
end

function f2tRegisterMapContent()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("fed2_map", buildContentDef())
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterMapContent)