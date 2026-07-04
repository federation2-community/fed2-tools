-- hauling_work_start — patterns declared in triggers.json
--
-- Header of the `work` job listing.  Feeds the Hauling Jobs panel and gags the
-- raw listing — but only when a panel is actually open, and never while the
-- hauling automation is running (its own capture owns the output then).
if F2T_HAULING_STATE and F2T_HAULING_STATE.active then return end
if f2tHaulingJobsHasOpenPanels and f2tHaulingJobsHasOpenPanels() then
    deleteLine()
    f2tHaulingJobsHeader()
end
