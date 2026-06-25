-- fed2-tools — Map content registration
--
-- Registers the Fed2 Map content with Muxlet: apply/remove lifecycle hooks that
-- mount and unmount the Geyser.Mapper widget inside a Muxlet pane.
--
-- f2tRegisterMapContent() is called from init.lua's muxletReady handler.

local function buildContentDef()
    -- Token-based guard: each apply mints a new token table.  The deferred timer
    -- checks this token before building; remove() clears it so a timer that fires
    -- after removal is a no-op (prevents orphaned mapper on rapid apply→remove).
    local activeToken = nil

    return {
        name        = "Fed2 Map",
        description = "Federation 2 mapper",
        singleton   = true,

        apply = function(target)
            closeMapWidget()
            target.contentBg:echo("")
            target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")

            -- Snapshot map emptiness BEFORE mounting the mapper.  Auto-mapping
            -- fires when the widget first renders, so checking after would give a
            -- false "has rooms" reading on a genuinely fresh profile.
            local preRooms   = getRooms()
            local mapIsEmpty = not preRooms or not next(preRooms)

            -- Use _gid (never recycled) for the widget name so that closing a
            -- pane and creating a new one with the same user-facing id does not
            -- alias the old mapper widget and show blank content.
            local mapperName = target._gid .. "_fed2mapper"
            local gid        = target._gid

            -- target.content points to the framework's slot container right now
            -- (during apply).  After this function returns, the framework restores
            -- target.content to the real pane container, so any deferred callback
            -- must capture the slot reference here before returning.
            local slotContent = target.content

            local myToken = {}
            activeToken = myToken

            tempTimer(0.1, function()
                if activeToken ~= myToken then return end
                activeToken = nil

                -- Build the mapper + overlays under pcall so that a failure here
                -- can never swallow the import-check scheduling below — that gap
                -- is what previously kept the first-run import dialog from firing.
                local ok, err = pcall(function()
                    Geyser.Mapper:new({
                        name   = mapperName,
                        x      = "0%",
                        y      = "0%",
                        width  = "100%",
                        height = "100%",
                    }, slotContent)
                    -- Track the mapper widget name so remove() can explicitly
                    -- hide it; closeMapWidget() alone does not always un-render
                    -- the Geyser.Mapper overlay on the target's content area.
                    target._activeMapperName = mapperName

                    -- Movement button overlay lives on top of the mapper.
                    if f2tBuildMapMovement then
                        local mvShell = f2tBuildMapMovement(slotContent, gid)
                        if mvShell then mvShell:raise() end
                    end

                    -- Settings gear (manual import/export) — top of the overlay stack.
                    if f2tBuildMapSettings then
                        local setShell = f2tBuildMapSettings(slotContent, gid)
                        if setShell then setShell:raise() end
                    end
                end)
                if not ok then
                    f2t_debug_log("[map content] overlay build error: %s", tostring(err))
                end

                -- Offer the map import dialog on first load / after an upgrade,
                -- OR whenever the map was empty before mounting.  mapIsEmpty is
                -- passed so f2tCheckMapImport can bypass the version-seen flag
                -- when the map was genuinely empty (user may have wiped it).
                tempTimer(0.5, function()
                    if f2tCheckMapImport then
                        f2tCheckMapImport(mapIsEmpty)
                    else
                        f2t_debug_log("[map content] f2tCheckMapImport missing — cannot offer import")
                    end
                end)
            end)
        end,

        -- Geyser.Mapper overlays the Geyser label rather than being a true Qt
        -- child of it, so hiding the parent container does not cascade to the
        -- mapper Qt widget.  Explicitly hide its Geyser representation first,
        -- then close the standalone mapper widget for belt-and-suspenders cleanup.
        remove = function(target)
            activeToken = nil
            if target._activeMapperName then
                pcall(function() hideWindow(target._activeMapperName) end)
                target._activeMapperName = nil
            end
            closeMapWidget()
        end,

    }
end

function f2tRegisterMapContent()
    Mux.registerContent("fed2_map", buildContentDef())
end
