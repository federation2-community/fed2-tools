-- fed2-tools map — Muxlet content registration
--
-- f2tRegisterMapContent() is called by the top-level init.lua inside
-- startWorkspace() so it always runs after Muxlet is confirmed available.

local function buildContentDef()
    return {
        name        = "Fed2 Map",
        description = "Federation 2 mapper",
        singleton   = true,

        apply = function(target)
            closeMapWidget()
            target.contentBg:echo("")
            target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")

            -- Defer mapper creation by one tick so the pane's content container
            -- geometry is fully resolved (important on same-session workspace apply).
            local mapperName = target.id .. "_fed2mapper"
            local capturedTarget = target
            tempTimer(0.1, function()
                local existing = Geyser.windowList[mapperName]
                if existing then
                    existing:show()
                    existing:raise()
                else
                    Geyser.Mapper:new({
                        name   = mapperName,
                        x      = "0%",
                        y      = "0%",
                        width  = "100%",
                        height = "100%",
                    }, capturedTarget.content)
                end
                -- Trigger map import dialog if the map DB is empty or an upgrade
                -- flagged a new database.  Deferred further so any onboarding
                -- dialog that just closed has a chance to finish animating out.
                tempTimer(0.5, function()
                    if f2tCheckMapImport then f2tCheckMapImport() end
                end)
            end)
        end,

        remove = function(target)
            local mapperName = target.id .. "_fed2mapper"
            if Geyser.windowList[mapperName] then
                Geyser.windowList[mapperName]:hide()
            end
        end,
    }
end

function f2tRegisterMapContent()
    Mux.registerContent("fed2_map", buildContentDef())
end

if Mux and Mux.registerContent then
    f2tRegisterMapContent()
end
