-- death_detected — patterns declared in triggers.json
--
-- Fires BEFORE the respawn teleport, allowing the killing-room location to be
-- captured before GMCP updates to the respawn point.

if not f2t_settings_get("death", "enabled") then
    return
end

if F2T_DEATH_STATE and F2T_DEATH_STATE.active then
    f2t_debug_log("[death] Death trigger fired but recovery already in progress")
    return
end

f2t_debug_log("[death] Death detected! Capturing location before respawn...")
f2t_death_start_recovery()