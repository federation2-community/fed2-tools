-- Galaxy Navigator capture terminator: the blank line after "di systems" ends
-- the capture and triggers the parse. Requires at least one captured line so
-- that a leading blank line in the output does not end capture prematurely.
if F2T_GALAXY and F2T_GALAXY.capture_active and #F2T_GALAXY.capture_lines > 0 then
    f2t_galaxy_finish_capture()
    deleteLine()
end