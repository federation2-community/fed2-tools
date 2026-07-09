-- Delete +++ exchange ticker announcements from the main console when the
-- exchange/console_spam setting is off.  The Exchange content still gets the
-- data via gmcp.exchange.commodity.

if f2t_settings_get("exchange", "console_spam") then return end

deleteLine()
-- The announcement block is followed by a blank line; eat that too.
tempLineTrigger(1, 1, function()
    if line == "" or line:match("^%s*$") then deleteLine() end
end)
