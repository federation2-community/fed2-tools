-- Out of fuel and stranded — buy fuel immediately. Gated by refuel/enabled.

if not f2t_settings_get("refuel", "enabled") then return end

f2t_debug_log("[refuel] EMERGENCY: out of fuel")
cecho("\n<red>[refuel]<reset> <yellow>EMERGENCY:<reset> Out of fuel! Buying fuel immediately...\n")
send("buy fuel", false)