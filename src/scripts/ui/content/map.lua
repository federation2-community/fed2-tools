-- fed2-tools — Map content registration
--
-- Registers the Fed2 Map content with Muxlet: apply/remove lifecycle hooks that
-- mount and unmount the Geyser.Mapper widget inside a Muxlet pane.
--
-- Why the mapper needs special handling
-- -------------------------------------
-- Muxlet tears down content by deleting the disposable Geyser.Container slot it
-- wraps each apply() in; that delete is recursive, so for ordinary widgets no
-- remove() cleanup is needed.  A Geyser.Mapper is the exception: the Mudlet map
-- widget it wraps is NOT a true Qt child of its parent container, so deleting the
-- slot does not remove it, and Mudlet exposes no deleteMapper().  The previous
-- implementation also created a brand-new mapper on every apply and only called
-- hideWindow() on remove (a no-op for a mapper) — so removing the map content
-- left the mapper painted over whatever replaced it, and repeated applies leaked
-- mappers.
--
-- The fix: keep ONE shared mapper for the whole session and move it between the
-- active content slot and a hidden "garage" container.  apply() acquires it into
-- the slot; remove() releases it back to the garage BEFORE the framework deletes
-- the slot, so it is never orphaned and never keeps drawing.
--
-- f2tRegisterMapContent() is called from init.lua's muxletReady handler.

-- ── Shared mapper management ────────────────────────────────────────────────────
local sharedMapper = nil
local mapperGarage = nil

-- Hidden 1x1 holder the mapper lives in whenever no pane is showing it.
local function ensureGarage()
    if mapperGarage then return mapperGarage end
    mapperGarage = Geyser.Container:new({
        name   = "f2t_mapper_garage",
        x      = 0, y = 0, width = "100%", height = "100%",
    })
    pcall(function() mapperGarage:hide() end)
    return mapperGarage
end

-- Acquire the shared mapper into `slotContent`, creating it on first use.
local function mapperAcquire(slotContent)
    ensureGarage()
    if not sharedMapper then
        sharedMapper = Geyser.Mapper:new({
            name   = "f2t_shared_mapper",
            x      = "0%", y = "0%",
            width  = "100%", height = "100%",
        }, slotContent)
    else
        pcall(function() sharedMapper:changeContainer(slotContent) end)
    end
    pcall(function()
        sharedMapper:move("0%", "0%")
        sharedMapper:resize("100%", "100%")
        sharedMapper:show()
        sharedMapper:reposition()
    end)
    -- The native map widget is a GL surface that does not reliably repaint just
    -- because its Geyser wrapper was reparented and re-shown — after a prior hide
    -- it commonly comes back blank.  Force a redraw now, then again on the next
    -- event-loop turn once the new geometry has actually been applied (the widget
    -- needs a tick after reparenting before resize/repaint takes).
    if updateMap then pcall(updateMap) end
    tempTimer(0.05, function()
        if not sharedMapper then return end
        pcall(function()
            sharedMapper:show()
            sharedMapper:resize("100%", "100%")
            sharedMapper:reposition()
        end)
        if updateMap then pcall(updateMap) end
    end)
    return sharedMapper
end

-- Park the shared mapper back in the hidden, full-size garage and hide it.
-- Called from remove() BEFORE the slot is destroyed so the mapper is never
-- orphaned in a deleted container.  Crucially it is NOT resized here: shrinking
-- it to a tiny garage collapsed the GL surface and it came back blank on the next
-- acquire.  The garage is full-window-size, so the parked mapper keeps a sane
-- size and only needs re-fitting to the new slot when re-acquired.
local function mapperRelease()
    if not sharedMapper then return end
    ensureGarage()
    pcall(function() sharedMapper:hide() end)
    pcall(function() sharedMapper:changeContainer(mapperGarage) end)
end

-- Refit the mapper to the current slot (called from resize()).
local function mapperFit()
    if not sharedMapper then return end
    pcall(function()
        sharedMapper:move("0%", "0%")
        sharedMapper:resize("100%", "100%")
        sharedMapper:reposition()
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
        singleton   = true,

        apply = function(target)
            target.contentBg:echo("")
            target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")

            -- Snapshot map emptiness BEFORE mounting the mapper.  Auto-mapping
            -- fires when the widget first renders, so checking after would give a
            -- false "has rooms" reading on a genuinely fresh profile.
            local preRooms   = getRooms()
            local mapIsEmpty = not preRooms or not next(preRooms)

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
                activeToken = nil

                -- Build the mapper + overlays under pcall so a failure here can
                -- never swallow the import-check scheduling below.
                local ok, err = pcall(function()
                    local mapper = mapperAcquire(slotContent)
                    target._f2tHasMapper = true
                    if mapper then mapper:raise() end

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

                -- Offer the map import dialog on first load / after an upgrade,
                -- OR whenever the map was empty before mounting.
                tempTimer(0.5, function()
                    if f2tCheckMapImport then
                        f2tCheckMapImport(mapIsEmpty)
                    else
                        f2t_debug_log("[map content] f2tCheckMapImport missing — cannot offer import")
                    end
                end)
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
        end,

        -- Keep the mapper filling the slot as the pane/tab is resized.
        resize = function(target)
            if target._f2tHasMapper then mapperFit() end
        end,
    }
end

function f2tRegisterMapContent()
    if not (Mux and Mux.registerContent) then return end
    Mux.registerContent("fed2_map", buildContentDef())
end