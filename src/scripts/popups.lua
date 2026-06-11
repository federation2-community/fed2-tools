-- fed2-tools — Welcome and upgrade dialogs
--
-- f2tCheckWelcome()  — entry point called from init.lua after fullStart().
--   Shows the full welcome dialog the first time ever (f2t.welcome_shown not set).
--   Shows the standalone workspace offer when WORKSPACE_OFFER_VERSION has been
--   bumped beyond what the user last responded to.
--
-- f2tShowOffer()  can also be called standalone (e.g. from a future command).
--
-- f2tOfferPending()  is a global used by import_check.lua to defer the map
--   import dialog until any visible offer has been dismissed.  No back-call
--   from offer into import; import re-checks on the next map content apply.
--
-- Upgrade trigger:
--   Bump  WORKSPACE_OFFER_VERSION  in this file when you want users to see
--   the workspace offer again on next session.

local WORKSPACE_OFFER_VERSION = 1

-- ── Settings helpers ──────────────────────────────────────────────────────────
-- Written directly to Mux.settings._data["f2t"]; no registry dependency.

local function welcomeShown()
    local d = Mux.settings and Mux.settings._data
    return d and d["f2t"] and d["f2t"]["welcome_shown"] == true
end

local function offerVersionSeen()
    local d = Mux.settings and Mux.settings._data
    return tonumber(d and d["f2t"] and d["f2t"]["workspace_offer_version_seen"]) or 0
end

function f2tOfferPending()
    return offerVersionSeen() < WORKSPACE_OFFER_VERSION
end

local function markWelcomeShown()
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["welcome_shown"] = true
    Mux.settings.save()
end

local function markOfferSeen()
    if not (Mux and Mux.settings) then return end
    Mux.settings._data["f2t"] = Mux.settings._data["f2t"] or {}
    Mux.settings._data["f2t"]["workspace_offer_version_seen"] = WORKSPACE_OFFER_VERSION
    Mux.settings.save()
end

-- ── Welcome body ──────────────────────────────────────────────────────────────

local _WELCOME_HTML =
    "<font color='#c6d2ee'>" ..
        "A living toolkit for Federation 2 that grows alongside you.<br>" ..
        "Each component is independent &mdash; use what suits your playstyle." ..
    "</font><br><br>" ..

    "<font color='#73de94'><b>COMPONENTS</b></font><br>" ..
    "<font color='#7ab4ff'>Map</font>" ..
        "<font color='#c6d2ee'> &mdash; Auto-mapper, speedwalk navigation, galaxy explorer</font><br>" ..
    "<font color='#7ab4ff'>Hauling</font>" ..
        "<font color='#c6d2ee'> &mdash; Rank-aware commodity trading automation</font><br>" ..
    "<font color='#7ab4ff'>Factory</font>" ..
        "<font color='#c6d2ee'> &mdash; Monitor all factory statuses at a glance</font><br>" ..
    "<font color='#7ab4ff'>Commodities</font>" ..
        "<font color='#c6d2ee'> &mdash; Price analysis and bulk buy/sell tools</font><br>" ..
    "<font color='#7ab4ff'>Refuel</font>" ..
        "<font color='#c6d2ee'> &mdash; Automatic ship refueling</font><br><br>" ..

    "<font color='#73de94'><b>MUXLET INTEGRATION</b></font><br>" ..
    "<font color='#c6d2ee'>" ..
        "Every component is available as <b>Muxlet content</b>.<br>" ..
        "Right-click any pane &rarr; <b>Add Content</b> to attach it wherever you like,<br>" ..
        "or apply the recommended workspace below." ..
    "</font>"

-- ── Shared workspace offer section ───────────────────────────────────────────
-- Builds the "apply workspace?" prompt into `parent` starting at `startY`.
-- `pfx` namespaces Geyser widget names.  `onApply`/`onSkip` are click callbacks.

local function buildWorkspaceOffer(parent, pfx, startY, onApply, onSkip)
    local div = Geyser.Label:new({
        name = pfx .. "div", x = 0, y = startY, width = "100%", height = 1,
    }, parent)
    div:setStyleSheet(Mux.dialogCss.divider)

    local prompt = Geyser.Label:new({
        name = pfx .. "prompt", x = "3%", y = startY + 8, width = "94%", height = 44,
    }, parent)
    prompt:setStyleSheet(Mux.dialogCss.subtext)
    prompt:echo(
        "Apply the recommended fed2-tools workspace?<br>"
        .. "<font color='rgba(75,90,130,255)'>"
        .. "You can also apply it later: <b>mux workspace load fed2-tools</b>"
        .. "</font>"
    )

    local btnApply = Geyser.Label:new({
        name = pfx .. "apply", x = "5%", y = startY + 60, width = "42%", height = 36,
    }, parent)
    btnApply:setStyleSheet(Mux.dialogCss.buttonPrimary)
    btnApply:echo("<center>Apply Workspace</center>")
    btnApply:setClickCallback(onApply)

    local btnSkip = Geyser.Label:new({
        name = pfx .. "skip", x = "53%", y = startY + 60, width = "42%", height = 36,
    }, parent)
    btnSkip:setStyleSheet(Mux.dialogCss.button)
    btnSkip:echo("<center>Not Now</center>")
    btnSkip:setClickCallback(onSkip)
end

-- ── Welcome dialog (full, shown once ever) ───────────────────────────────────

function f2tShowWelcome()
    if not (Mux and Mux.createDialog) then
        cecho(
            "\n<cyan>[fed2-tools]<reset> <white>Welcome!<reset>"
            .. " Apply the recommended workspace: <cyan>mux workspace load fed2-tools<reset>\n"
        )
        markWelcomeShown()
        markOfferSeen()
        return
    end

    local dialog = Mux.createDialog({
        title  = "Welcome to fed2-tools",
        width  = 520,
        height = 420,
    })
    local c   = dialog.content
    local pfx = dialog._gid .. "_wlc_"

    local body = Geyser.Label:new({
        name = pfx .. "body", x = "2%", y = 8, width = "96%", height = 215,
    }, c)
    body:setStyleSheet([[
        background: transparent;
        color: rgba(198,210,238,255);
        font-size: 10px;
        padding: 4px 14px;
    ]])
    body:echo(_WELCOME_HTML)

    markWelcomeShown()

    buildWorkspaceOffer(c, pfx, 230,
        function()
            markOfferSeen()
            dialog:close()
            Mux.applyWorkspace("fed2-tools")
        end,
        function()
            markOfferSeen()
            dialog:close()
        end
    )

    dialog:show()
    dialog:raise()
end

-- ── Workspace offer dialog (standalone, shown when version incremented) ───────

function f2tShowOffer()
    if not (Mux and Mux.createDialog) then
        cecho(
            "\n<cyan>[fed2-tools]<reset> An updated workspace is available:"
            .. " <cyan>mux workspace load fed2-tools<reset>\n"
        )
        markOfferSeen()
        return
    end

    local dialog = Mux.createDialog({
        title  = "fed2-tools — Workspace Update",
        width  = 480,
        height = 180,
    })
    local c   = dialog.content
    local pfx = dialog._gid .. "_ofc_"

    buildWorkspaceOffer(c, pfx, 8,
        function()
            markOfferSeen()
            dialog:close()
            Mux.applyWorkspace("fed2-tools")
        end,
        function()
            markOfferSeen()
            dialog:close()
        end
    )

    dialog:show()
    dialog:raise()
end

-- ── Public entry point ────────────────────────────────────────────────────────

function f2tCheckWelcome()
    if not welcomeShown() then
        f2tShowWelcome()
    elseif f2tOfferPending() then
        f2tShowOffer()
    end
end
