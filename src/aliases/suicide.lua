-- suicide_detect — regex declared in aliases.json
--
-- Intercept the suicide command so the death monitor knows the cause, which
-- prevents the room being auto-locked after an intentional death.

if f2t_death_detect_suicide then
    f2t_death_detect_suicide()
end

send("suicide")