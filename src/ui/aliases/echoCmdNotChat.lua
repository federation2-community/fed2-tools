-- @patterns:
--   - pattern: ^(?!(?:tb|tell)\s+\w+\s+|(?:com|comm|say)\s+|[''"]{1,2}\s*|lua\s+|=)(.+)$

-- This is a general alias for all commands except chat ones, needed to avoid console echo on chat commands but provide it for all others
hecho("#808000" .. matches[1])

send(matches[1], false)