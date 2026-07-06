-- comhistory_line — patterns declared in triggers.json
--
-- Fires on every line (pattern is a catch-all) so it can reliably see both
-- historical com message headers AND their wrapped continuation lines in
-- order, even when the whole comhistory response arrives as one batch — a
-- tempLineTrigger armed mid-batch would register one line too late and
-- desync (see comhistory.lua). f2tChatComhistoryLine() no-ops immediately
-- unless a backfill capture is active.
f2tChatComhistoryLine()
