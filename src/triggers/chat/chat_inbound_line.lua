-- chat_inbound_line — patterns declared in triggers.json
--
-- Fires on every line (catch-all pattern) so a wrapped live message's
-- continuation lines are never missed regardless of how the game batches
-- output. f2tChatInboundLine() no-ops immediately unless a message is
-- currently pending completion (see chat_inbound.lua).
f2tChatInboundLine()
