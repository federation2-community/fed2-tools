-- A blank line while a galaxy scrape is active: hidden (still part of the
-- automated background command) and treated as activity, not as "the"
-- terminator — Fed2's login sequence can interleave unrelated blank lines
-- mid-response, and ending capture on the first one leaked the rest of the
-- (much longer) listing. Completion is purely silence-timer driven; see
-- f2t_galaxy_capture_blank / resetFinishTimer in galaxy.lua.
if F2T_GALAXY and F2T_GALAXY.capture_active then
    deleteLine()
    f2t_galaxy_capture_blank()
end