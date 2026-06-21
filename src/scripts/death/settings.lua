-- fed2-tools death monitor — settings registration
--
-- Namespace "death" (own module) so it gets its own settings-UI tab; Muxlet
-- fixes a namespace's tab path on first registration, so sharing a namespace
-- across modules would collapse them into one tab.  Legacy `validator` dropped
-- (the toggle widget constrains the value).

f2t_settings_register("death", "enabled", {
    tab         = "Fed2-Tools/Death Monitor",
    description = "Automatic death recovery: capture death location, re-insure, lock the killing room",
    default     = true,
})