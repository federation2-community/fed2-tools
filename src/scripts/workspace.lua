-- fed2-tools — Muxlet workspace definition
--
-- f2tRegisterWorkspace() is called by init.lua inside startWorkspace() so it
-- always runs after Muxlet is confirmed available, whether it was already
-- installed or was just installed this session.
--
-- A single screen-zone PaneSet with an internal horizontal split keeps the
-- output and map panes in the same layout tree.  This means:
--   • Splitting the output pane creates sub-splits that stay within slotA;
--     the map pane in slotB is never covered.
--   • Console borders are set correctly by updateConsoleBorders on the output
--     pane rather than by a separate right-zone border management pass.
--   • The "fed2_map" content is applied automatically at load time via
--     activeContent, so init.lua does not need a manual applyMapContent call
--     for initial workspace startup.

local function buildDef()
    return {
        name        = "Federation 2 Tools",
        description = "Recommended workspace for Federation 2",
        theme       = "dark",
        paneSets = {
            {
                id   = "main",
                zone = "screen",
                root = {
                    type      = "split",
                    direction = "h",
                    ratio     = 0.72,
                    a = {
                        type            = "pane",
                        id              = "output",
                        name            = "Main",
                        mainConsoleHost = true,
                        showTitlebar    = true,
                        noRename        = true,
                        noTabs          = true,
                    },
                    b = {
                        type          = "pane",
                        id            = "map",
                        name          = "Map",
                        showTitlebar  = true,
                        noRename      = true,
                        noTabs        = true,
                        activeContent = "fed2_map",
                    },
                },
            },
        },
    }
end

function f2tRegisterWorkspace()
    Mux.registerWorkspace("fed2-tools", buildDef())
end

if Mux and Mux.registerWorkspace then
    f2tRegisterWorkspace()
end
