-- fed2-tools — Built-in workspace definitions
--
-- Registers the workspace(s) shipped with the package so the Full Experience
-- welcome option (ui/dialogs/popups.lua) can load one on any installation,
-- not just profiles where a user has saved it locally.
--
-- Regenerate this file after changing the layout in-game:
--   mux workspace save fed2-tools
--   mux workspace export fed2-tools
-- then copy the printed export file over this one and rebuild.
-- (mux workspace export requires a Muxlet build with that command; see
-- Muxlet's src/scripts/workspace.lua and src/aliases/mux.lua.)

local function f2tRegisterWorkspaces()
    Mux.registerWorkspace("fed2-tools", {
        paneSpace = {
            root = {
                a = {
                    a = {
                        a = {
                            closeable = false,
                            mainConsoleHost = false,
                            showTitlebar = false,
                            contentable = false,
                            renamable = false,
                            activeTabName = "Who",
                            nameAlign = "center",
                            minimizable = false,
                            tabsLocked = true,
                            type = "pane",
                            convertible = false,
                            id = "pane_2",
                            splittable = false,
                            zoomable = false,
                            name = "LeftTop",
                            swappable = false,
                            anchorable = true,
                            bordered = false,
                            tabs = {
                                {
                                    closeable = false,
                                    propertiesButton = false,
                                    contentable = false,
                                    renamable = false,
                                    movable = true,
                                    contentState = {},
                                    nameAlign = "center",
                                    name = "Who",
                                    _activeContent = "fed2_who"
                                }
                            },
                            movable = false
                        },
                        type = "split",
                        b = {
                            closeable = false,
                            mainConsoleHost = false,
                            showTitlebar = false,
                            contentable = false,
                            renamable = false,
                            swappable = false,
                            nameAlign = "center",
                            anchorable = true,
                            tabsLocked = true,
                            type = "pane",
                            convertible = false,
                            id = "pane_4",
                            name = "LeftBottom",
                            movable = false,
                            splittable = false,
                            bordered = false,
                            tabs = {
                                {
                                    closeable = false,
                                    propertiesButton = false,
                                    contentable = false,
                                    renamable = false,
                                    movable = true,
                                    contentState = {
                                        showTs = false,
                                        filterIdx = 1
                                    },
                                    nameAlign = "center",
                                    name = "Chat",
                                    _activeContent = "fed2_chat"
                                }
                            },
                            activeTabName = "Chat"
                        },
                        ratio = 0.5,
                        direction = "v"
                    },
                    type = "split",
                    b = {
                        a = {
                            closeable = false,
                            mainConsoleHost = false,
                            showTitlebar = false,
                            contentable = false,
                            renamable = false,
                            movable = false,
                            nameAlign = "center",
                            anchorable = true,
                            type = "pane",
                            convertible = false,
                            id = "pane_3",
                            zoomable = false,
                            name = "Top",
                            contentState = {},
                            splittable = false,
                            activeContent = "fed2_player_info",
                            swappable = false
                        },
                        type = "split",
                        b = {
                            closeable = false,
                            propertiesButton = false,
                            mainConsoleHost = true,
                            showTitlebar = true,
                            renamable = false,
                            swappable = false,
                            lockSnapshot = {
                                closeable = false,
                                convertible = false,
                                movable = true
                            },
                            addable = false,
                            minimizable = false,
                            type = "pane",
                            convertible = false,
                            id = "output",
                            activeContent = "mux_console",
                            name = "Mudlet",
                            splittable = false,
                            movable = false,
                            bordered = false,
                            nameAlign = "center",
                            anchorable = true
                        },
                        ratio = 0.040915972747918,
                        direction = "v"
                    },
                    ratio = 0.25073457394711,
                    direction = "h"
                },
                type = "split",
                b = {
                    a = {
                        closeable = false,
                        mainConsoleHost = false,
                        showTitlebar = false,
                        contentable = false,
                        renamable = false,
                        activeTabName = "Map",
                        nameAlign = "center",
                        minimizable = false,
                        tabsLocked = true,
                        type = "pane",
                        convertible = false,
                        id = "pane_1",
                        splittable = false,
                        zoomable = false,
                        name = "RightTop",
                        swappable = false,
                        anchorable = true,
                        bordered = false,
                        tabs = {
                            {
                                renamable = false,
                                propertiesButton = false,
                                movable = true,
                                name = "Map",
                                nameAlign = "center",
                                _activeContent = "fed2_map",
                                closeable = false,
                                contentable = false
                            }
                        },
                        movable = false
                    },
                    type = "split",
                    b = {
                        closeable = false,
                        mainConsoleHost = false,
                        showTitlebar = true,
                        contentable = false,
                        renamable = false,
                        swappable = false,
                        nameAlign = "center",
                        minimizable = false,
                        type = "pane",
                        convertible = false,
                        id = "pane_5",
                        movable = false,
                        zoomable = false,
                        name = "RightBottom",
                        splittable = false,
                        anchorable = true,
                        bordered = false,
                        tabs = {
                            {
                                closeable = true,
                                name = "Hauling",
                                nameAlign = "center",
                                renamable = false,
                                movable = true,
                                contentable = true
                            },
                            {
                                closeable = true,
                                name = "Trading",
                                nameAlign = "center",
                                renamable = false,
                                movable = true,
                                contentable = true
                            },
                            {
                                closeable = false,
                                name = "Company",
                                nameAlign = "center",
                                renamable = false,
                                movable = true,
                                contentable = true
                            }
                        },
                        activeTabName = "Hauling"
                    },
                    ratio = 0.5,
                    direction = "v"
                },
                ratio = 0.79976535001955,
                direction = "h"
            },
            zone = "screen",
            id = "screen",
            size = "20%"
        },
        name = "fed2-tools",
        theme = "dark",
        floatingPanes = {}
    })
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterWorkspaces)
