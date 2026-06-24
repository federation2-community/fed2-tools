-- Galaxy Navigator capture: buffers each "di systems" line while a navigator
-- scrape is active, and hides it from the main console. Inert otherwise, so a
-- manual "di systems" still prints normally.
if F2T_GALAXY and F2T_GALAXY.capture_active then
    f2t_galaxy_capture_line(matches[2])
    deleteLine()
end