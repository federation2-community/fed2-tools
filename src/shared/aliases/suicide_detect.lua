-- @patterns:
--   - pattern: ^suicide$

-- Intercept the suicide command so the death monitor knows the cause,
-- preventing the room from being auto-locked after the death.
if f2t_death_detect_suicide then
    f2t_death_detect_suicide()
end

send("suicide")
