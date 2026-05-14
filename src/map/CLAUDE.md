# Map Component

Custom mapper for Federation 2, built on Mudlet's mapper API.

## Overview

Automatically creates and maintains a navigable map using GMCP room data. Features auto-mapping, hash-based room IDs, speedwalk navigation, and saved destinations.

## Key Features

- **Auto-mapping**: Creates rooms/exits as you explore
- **GMCP Integration**: Uses `gmcp.room.info` for room data
- **Hash-based IDs**: Maps Fed2 room identifiers (`system.area.num`) to Mudlet room IDs
- **Speedwalk**: `nav` command with multiple resolution formats
- **Saved Destinations**: Quick navigation to favorite locations
- **Manual Mapping**: Create/edit rooms and exits to supplement auto-mapping
- **Jump Integration**: Parse jump destinations, create special exits

## Usage

### Commands Overview

**Map Control:**
- `map on/off` - Enable/disable auto-mapping
- `map sync` - Force sync with GMCP
- `map clear` - Clear entire map (with confirmation)
- `map confirm` - Confirm pending destructive operation (30s timeout)
- `map cancel` - Cancel pending confirmation
- `map export` - Export map to JSON file (opens file dialog)
- `map import` - Import map (shows summary, use `map confirm` to proceed)

**Diagnostics:**
- `map raw` - Show raw mapper + GMCP data for current room
- `map raw <room_id>` - Show raw mapper data for specified room

**Navigation:**
- `nav <destination>` - User-saved destination (highest priority)
- `nav <room_id>` - Mudlet room ID
- `nav <system>.<area>.<num>` - Fed2 hash
- `nav <planet>` - Navigate to planet (default: shuttlepad, configurable)
- `nav <planet> orbit` - Navigate to planet's orbit
- `nav <system>` - Navigate to system's link room
- `nav <flag>` - Navigate to flag in current area
- `nav <area> <flag>` - Navigate to flag in specified area

**Flag Shortcuts:** `ex` → `exchange`, `sp` → `shuttlepad`

**Speedwalk Control:**
- `nav stop` or `stop` - Stop speedwalk
- `nav pause` or `pause` - Pause speedwalk
- `nav resume` or `resume` - Resume speedwalk

**Settings:**
- `map settings` - List all settings
- `map settings set enabled true/false` - Enable/disable mapping
- `map settings set planet_nav_default shuttlepad/orbit` - Default planet destination

**Saved Destinations:**
- `map dest` - List all
- `map dest add <name>` - Save current location
- `map dest remove <name>` - Remove destination

**Jump Exits:**
- Automatically created when entering link rooms
- No manual action required

**Search Rooms:**
- `map search <text>` - Search current area for room name
- `map search <planet|system> <text>` - Search planet or system
- `map search all <text>` - Search all areas

**Special Navigation:**

*On-Arrival Commands:*
- `map special arrival <command>` - Set command (runs every time)
- `map special arrival <type> <command>` - Set command with execution type
- `map special arrival remove` - Remove on-arrival command
- `map special arrival list` - List all rooms with on-arrival commands

*Execution Types:*
- `always` - Run every time (default)
- `once-room` - Run once, then disable
- `once-area` - Run once per area visit (resets when leaving area)
- `once-ever` - Run once ever, then disable permanently

*Special Exits:*
- **Note**: Special exits are now managed via `map exit special` (see Manual Mapping section below)

### Exploration Modes

**Automated exploration with four-layer architecture and full|brief options:**

**Commands:**
- `map explore` - Context-aware exploration (brief mode)
- `map explore [target]` - Explore target (auto-detect planet/system, brief mode)
- `map explore full [target]` - Full exploration (all rooms)
- `map explore brief [target]` - Brief exploration (flag discovery)
- `map explore cartel [cartel]` - Explore all systems in cartel (brief mode only)
- `map explore galaxy` - Explore all cartels in galaxy (brief mode only)

**Control:**
- `map explore stop` - Stop exploration
- `map explore pause` - Pause exploration
- `map explore resume` - Resume paused exploration
- `map explore status` - Show exploration status

**Mode Options:**
- **full** - Complete DFS exploration (discovers all rooms)
- **brief** - Quick discovery (stops when targets found)

**Target Auto-Detection:**
- Target names are auto-detected as planet or system
- If a name matches both (e.g., "Sol" is both system and planet), prefer unexplored system
- If system is fully mapped, explore the planet instead

**How It Works:**

*Planet Mode (Layer 1 - Brief):*
- Lightweight exploration from current room
- Searches in concentric circles (distance-sorted DFS)
- Stops when target flags found (shuttlepad, exchange by default)
- Used by system/cartel modes for quick planet discovery

*Planet Mode (Layer 1 - Full):*
- Complete DFS exploration of entire area
- Maps every room until no stub exits remain
- Use for full planet/area mapping

*System Mode (Layer 2 - Brief):*
- Explores all planets in a system efficiently
- **Phase 1:** Maps space area to discover planets
  - Runs `di system <system>` to get expected planet list
  - Stops Phase 1 when all expected planets' orbits found (early exit)
- **Phase 2:** Brief exploration of each planet (find shuttlepad + exchange only)
- Skips already-mapped planets

*System Mode (Layer 2 - Full):*
- Explores all planets in a system comprehensively
- **Phase 1:** Complete DFS of entire space area (all rooms)
  - No early exit - explores every room regardless of planet discovery
- **Phase 2:** Brief exploration of each planet (find shuttlepad + exchange only)
- Skips already-mapped planets

*Cartel Mode (Layer 3):*
- Explores all systems in a cartel (brief mode only)
- Captures `display cartel` output to get system list
- For each system: navigate to link → jump → invoke system mode (brief)
- Skips already-mapped systems

*Galaxy Mode (Layer 4):*
- Explores all cartels in the galaxy (brief mode only)
- Captures `display cartels` output to get cartel list
- For each cartel: navigate to link → jump → invoke cartel mode (brief)
- Skips already-explored cartels (all systems mapped)
- Primary system for each cartel = cartel name (e.g., "Frontier" cartel → "Frontier" system)

**Four-Layer Architecture:**

```
Galaxy Mode (Layer 4) - brief only
  └─> For each cartel:
        └─> Cartel Mode (Layer 3) - brief only
              └─> For each system:
                    └─> System Mode (Layer 2) - brief only in nested
                          ├─> Phase 1: Explore space area
                          │   - Stop when expected planets found (DI system)
                          └─> Phase 2: For each planet:
                                └─> Planet Mode (Layer 1) - brief only in nested
                                      └─> Find shuttlepad + exchange
```

**Nested Mode Pattern:**

Each layer can run standalone OR nested:
- **Standalone**: Full initialization with `mode = "planet"|"system"|"cartel"|"galaxy"`
- **Nested**: Preserves parent `mode`, adds layer-specific fields, uses callbacks

**Planet Mode State Fields:**
- `mode = "planet"` - Layer 1 exploration
- `planet_mode = "full" | "brief"` - DFS or flag-finding mode

Example: Cartel → System delegation (with mode parameter):
```lua
-- Cartel passes "brief" mode and callback to system
f2t_map_explore_system_start(system_name, "brief", function()
    f2t_map_explore_cartel_next_system()  -- Resume cartel after system done
end)

-- System mode signature:
-- f2t_map_explore_system_start(system_name, system_mode, on_complete_callback)
-- - system_mode: "full" or "brief" (default: "brief")
-- - on_complete_callback: nil (standalone) or function (nested)

-- System mode checks callback parameter:
if on_complete_callback then
    -- NESTED: Don't overwrite parent mode, preserve "cartel"
    -- Force brief mode when nested (requirement)
    F2T_MAP_EXPLORE_STATE.system_name = system_name
    F2T_MAP_EXPLORE_STATE.system_mode = "brief"  -- Always brief in nested
    F2T_MAP_EXPLORE_STATE.system_complete_callback = on_complete_callback
else
    -- STANDALONE: Full init with mode = "system"
    F2T_MAP_EXPLORE_STATE.mode = "system"
    F2T_MAP_EXPLORE_STATE.system_mode = system_mode  -- User-specified
end
```

This pattern allows:
- ✅ Parent state preserved (mode stays "cartel" during system exploration)
- ✅ Parent callbacks work (system calls back to cartel on completion)
- ✅ Each layer can run independently or nested
- ✅ Clean separation of concerns (each layer focused on its job)
- ✅ Mode flexibility in standalone, efficiency in nested

**Key Implementation Files:**
- `map_explore.lua` - Core state machine, Layer 1 planet exploration (full/brief), router
- `map_explore_system.lua` - Layer 2 (system mode with full/brief, delegates to planet brief)
- `map_explore_system_helpers.lua` - System planet tracking (brief mode early exit)
- `map_explore_cartel.lua` - Layer 3 (cartel mode, delegates to system with brief)
- `map_explore_galaxy.lua` - Layer 4 (galaxy mode, delegates to cartel)
- `map_di_system_capture.lua` - DI system capture for expected planets list
- `map_explore_escape.lua` - Escape from unmapped rooms, stranded handling

**Stranded Recovery (One-Way Exit Handling):**

Exploration may discover rooms via one-way exits (can enter but mapped exits don't lead back). To ensure navigation works for the next phase, exploration returns to a safe location before calling completion callbacks:

- **Brief mode (planet):** Returns to shuttlepad before callback
- **System mode:** Returns to link room before callback

*How it works:*
1. Exploration completes (all flags found / all planets briefed)
2. Before calling completion callback, navigates to safe location
3. If navigation fails (stranded in unmapped room):
   - Enters "escape mode" - walks GMCP exits until navigation works
   - GMCP provides valid exits even when Mudlet map doesn't know them
   - Each exit walked creates map connections via auto-mapping
   - Retries navigation after each step
4. On success: continues to safe location, then calls callback
5. On failure (after max attempts): pauses exploration for manual intervention

*Recovery from stranded pause:*
- `map explore status` - Shows stranded state and target destination
- User manually navigates to a known location (any mapped room)
- `map explore resume` - Retries escape procedure from new location
- `map explore stop` - Aborts exploration entirely

*Why this matters:*
- Galaxy/system exploration can take 30+ minutes
- Without stranded recovery, one-way exit would require starting over
- Escape procedure handles common case (1-2 rooms from mapped network)
- Manual pause fallback preserves progress for edge cases

## Manual Mapping (Supplement Auto-Mapping)

**IMPORTANT PRINCIPLE:** Manual mapping is for **corrections and special cases**, NOT primary workflow.

**Primary Workflow:** Auto-mapping creates rooms/exits as you explore → **Recommended approach**
**Manual Workflow:** Use manual commands to fix errors or handle edge cases auto-mapping can't handle

### When to Use Manual Mapping

✅ **Use manual mapping for:**
- Correcting misplaced rooms or wrong coordinates
- Creating stub rooms for unmapped areas (testing, planning)
- Adding missing exits auto-mapping missed
- Handling special movement that doesn't trigger GMCP (e.g., teleports)
- Locking dangerous rooms/exits from navigation

❌ **Don't use manual mapping for:**
- Primary exploration (let auto-mapping do this)
- Standard room/exit creation (GMCP handles this)

### Room Management

**Create rooms:**
```
map room add <system> <area> <num> [name]    # Create new room with Fed2 hash
```

**Delete rooms:**
```
map room delete [room_id]                    # Delete (defaults to current, requires confirmation)
```

**View room info:**
```
map room info [room_id]                      # Display all properties (defaults to current)
```

**Edit room properties:**
```
map room set name [room_id] <name>           # Change name (defaults to current room)
map room set area [room_id] <area>           # Move to different area
map room set coords [room_id] <x> <y> <z>    # Reposition on map
map room set symbol [room_id] <char>         # Set symbol (1 character)
map room set color [room_id] <r> <g> <b>     # Set color (RGB 0-255)
map room set env [room_id] <env_id>          # Set environment ID
map room set weight [room_id] <weight>       # Set pathfinding weight (≥1, higher = avoid)
```

### Exit Management

**Standard exits:**
```
map exit add <from> <to> <dir>                      # Create one-way exit
map exit remove <room> <dir>                        # Remove exit (requires confirmation)
map exit list <room>                                # List all exits (standard + special)
```

**Note:** For bidirectional exits, use two `map exit add` commands (one for each direction).

**Special exits (Discovery Method - RECOMMENDED):**
```
# At source room:
map exit special <command>                # Test command, auto-creates exit on room change
map exit special reverse [cmd]            # At destination, creates return exit

# Examples:
map exit special press touchpad          # Tests "press touchpad", creates exit when you move
map exit special reverse                  # Creates reverse exit with same command
map exit special noop                     # For auto-transit rooms (waits for GMCP)
```

**Special exits (Manual Method - if you know room IDs):**
```
map exit special <dest> <cmd>             # From current room to dest
map exit special <src> <dest> <cmd>       # From src to dest
```

**Special exits (Management):**
```
map exit special list [room]              # List special exits
map exit special remove <cmd>             # Remove from current room
map exit special remove <room> <cmd>      # Remove from specific room
```

### Lock Management

**Lock rooms/exits** to prevent pathfinding through them (replaces old blacklist system):

```
map room lock [room_id]                   # Lock room (defaults to current, navigation will avoid)
map room unlock [room_id]                 # Unlock room
map room info [room_id]                   # Show room info including lock status

map exit lock [room_id] <dir>             # Lock specific exit (defaults to current room)
map exit unlock [room_id] <dir>           # Unlock exit
```

### Stub Exit Management

**Stub exits** are placeholders for unexplored exits. Useful when GMCP reports an exit direction but you haven't visited the destination yet.

```
map exit stub create [room_id] <dir>      # Create stub exit (defaults to current room)
map exit stub delete [room_id] <dir>      # Delete stub exit
map exit stub connect [room_id] <dir>     # Connect stub to destination
map exit stub list [room_id]              # List all stub exits (defaults to current room)
```

**How stub connection works:**
- Mudlet automatically finds rooms with matching opposite stubs in the correct direction
- Example: North stub in room A connects to room B with south stub
- Both rooms must exist and have appropriate stubs for connection to work

**Note:** Destructive operations (delete room, remove exit, import) require confirmation by default. Use `map confirm` or `map cancel` to approve/reject pending operations. Confirmations can be disabled: `map settings set map_manual_confirm false`

## Room Identification

Federation 2 uses: `system.area.num`

Example: `Coffee.Latte.459` = System "Coffee", Area "Latte", Room 459

Stored in Mudlet via `setRoomIDbyHash()` / `getRoomIDbyHash()`.

## Room Flags and Styling

Room styling uses emoji symbols and Mudlet environment IDs for background colors.

**Flag Detection:**
- `orbit` flag: Set when GMCP flags contain "orbit" OR `gmcp.room.info.orbit` is present
- `space` flag: Set when GMCP flags contain "space" OR area name ends with " Space"

| Flag | Symbol | Env ID | Color | Description |
|------|--------|--------|-------|-------------|
| shuttlepad | 🚀 | 257 | Red | Board/disembark ships |
| exchange | 💰 | 266 | Light Green | Commodity trading |
| orbit | 🪐 | 258 | Green | Orbital station (above planet) |
| link | 🔗 | 262 | Cyan | Jump to other systems |
| space (default) | (none) | 264 | Black | Space location |
| planet (default) | (none) | 272 | Light Black | Standard planet room |

**Priority:** shuttlepad > exchange > orbit > link (first match wins)

**Note:** Orbit takes precedence over link for rooms with both flags.

## How It Works (Simplified)

### 1. Initialization
- Declares `mudlet.mapper_script = true`
- Loads settings from `f2t_settings.map`
- Creates initial map if none exists

### 2. GMCP Event Handler (`gmcp.room.info`)
On room change:
1. Extract room data, generate hash
2. Check if room exists via `getRoomIDbyHash()`
3. If new: create room, set hash, name, area, coordinates, styling
4. Update exits from GMCP
5. Center map view

### 3. Room Creation
- Generate unique hash from Fed2 data
- Create Mudlet room with `createRoomID()`
- Store hash→ID mapping
- Set properties (name, environment, user data)

**Room User Data:**
- `fed2_system`, `fed2_area`, `fed2_num`, `fed2_owner`, `fed2_flags`, `fed2_planet` (orbit rooms only)

### 4. Area Management
- Check if area exists, create if needed
- Store area metadata (`fed2_system`, `fed2_cartel`, `fed2_owner`)

### 5. Exit Handling
- GMCP provides `exits` table: `{direction = room_num}`
- Create stub exits initially
- When moving through exit, connect stub to actual room
- Special exits: `board` (orbit/shuttlepad), `jump` (link rooms)

### 6. Coordinate System
Auto-layout with y-axis inversion (Fed2 uses top-left origin, Mudlet uses center):
- North: (0, -1, 0)
- South: (0, +1, 0)
- East: (+1, 0, 0)
- West: (-1, 0, 0)
- etc.

### 7. Navigation Resolution Order
1. **Saved destination** (user-defined)
2. **Pure number** → Mudlet room ID
3. **Contains dots** → Fed2 hash
4. **Two words** → Area + flag
5. **Single word** → Planet → System → Flag

### 8. Jump System (Auto-Discovery)
When entering a link room:
1. Automatically sends `jump` command (silent)
2. Triggers capture output (Inter-Cartel + Local destinations)
3. For each destination system:
   - Find link room in that system (by system name + "link" flag)
   - Create bidirectional special exits: `jump <system>`
4. Enables `getPath()` to plan routes through jump gates
5. Only creates exits for systems where we have mapped link rooms

**Key files:**
- `scripts/map_jump.lua` - Capture state and exit creation
- `triggers/jump_capture_*.lua` - Parse jump command output

### 9. Saved Destinations
- Stored as Fed2 hashes in `f2t_settings.map.destinations`
- Independent of map state
- Persist across map clears
- Resolved first in navigation

### 10. Speedwalk Movement Verification and Auto-Recovery

Speedwalk includes automatic movement verification and retry logic to handle failures gracefully.

**Movement Verification System:**

Every movement command is verified to ensure it succeeded:

1. **Before sending command**: Store expected destination room ID (from speedWalkPath) and start timeout timer (default: 2 seconds)
2. **After GMCP update**: Verify we arrived at the expected room
3. **On success**: Current room matches expected room → Reset failure counter, continue to next step
4. **On failure**: Current room does NOT match expected room → Increment failure counter, trigger recovery

**Failure Detection:**

Movement failures are detected in two ways:

1. **Wrong room**: GMCP arrives but current room ≠ expected room (includes: blocked exit/same room, wrong exit taken/different room, or manual interference)
2. **Timeout**: No GMCP response after timeout period (stuck, connection issue)

**Automatic Recovery:**

When movement fails, speedwalk automatically retries:

1. **First failure**: Recompute path from current location to destination, retry
2. **Second failure**: Recompute again, retry
3. **Third failure**: Stop speedwalk with error message

After **any successful movement**, failure counter resets to 0.

**Configuration:**

```
map settings set speedwalk_timeout 3        # 3-second timeout (range: 1-10)
map settings set speedwalk_max_retries 3    # 3 retry attempts (range: 1-10)
```

**Interruption Recovery:**

Speedwalk also handles specific interruption types automatically:

1. **Out of Fuel**: When ship runs out of fuel during space travel
   - Detects "You have run out of fuel, and are unable to move."
   - Waits for refuel component to buy fuel (1.5s)
   - Retries last movement command
   - Continues speedwalk automatically

2. **Sol Customs Intercept**: Random intercept by customs in Sol Space
   - Detects completion message: "leaving you alone to find your own way back to the main space lanes"
   - Waits for GMCP to update (0.5s)
   - Recomputes path from new location to original destination
   - Resumes speedwalk with new path

**Navigation Ownership Model:**

Components that use navigation can register ownership to receive interrupt callbacks instead of interrupt handlers containing component-specific code.

**State Variables:**
```lua
F2T_SPEEDWALK_OWNER = nil              -- Component name: "map-explore", "stamina", "hauling", nil
F2T_SPEEDWALK_ON_INTERRUPT = nil       -- Callback: function(reason) -> { auto_resume = bool }
```

**Helper Functions:**
```lua
-- Set ownership before starting navigation
f2t_map_set_nav_owner("component-name", function(reason)
    -- Handle interrupt (pause state, track reason, etc.)
    -- reason: "customs" or "out_of_fuel"
    return { auto_resume = true }  -- Request auto-resume after interrupt
end)

-- Clear ownership (called automatically in speedwalk_complete/stop)
f2t_map_clear_nav_owner()
```

**How It Works:**

1. Component calls `f2t_map_set_nav_owner()` before starting navigation
2. When interrupt occurs (customs, out-of-fuel), handler checks for callback
3. If callback exists: invoke with reason, use return value to decide auto-resume
4. If no callback (standalone navigation): default to auto-resume
5. Ownership cleared automatically when speedwalk completes or stops

**Interrupt Callback Pattern:**
```lua
-- In component start function:
f2t_map_set_nav_owner("my-component", function(reason)
    f2t_debug_log("[my-component] Navigation interrupted by %s", reason)

    if reason == "customs" then
        -- Customs stops speedwalk entirely - may need to pause component
        MY_STATE.paused = true
        MY_STATE.paused_reason = reason
    end
    -- out_of_fuel: speedwalk stays active, just retries after refuel

    return { auto_resume = true }
end)

-- Start navigation
f2t_map_navigate(destination)
```

**Callback Return Values:**
- `{ auto_resume = true }` - Interrupt handler will auto-resume navigation after delay
- `{ auto_resume = false }` - Component handles resume itself (speedwalk stops)
- `nil` or error - Defaults to auto-resume for safety

**Exception Safety:**
- Callbacks are wrapped in `pcall()` to prevent errors from breaking speedwalk state
- On callback error, defaults to auto-resume behavior

**Benefits:**
- ✅ Decoupled: Interrupt handlers don't know about specific components
- ✅ Extensible: New components just register callback, no trigger modifications
- ✅ Debuggable: Owner field shows who's navigating in debug logs
- ✅ Safe: pcall wrapper prevents callback errors from corrupting state

**General Speedwalk Benefits:**

- ✅ Catches all failure types (blocked exits, wrong exits, errors, unknown messages)
- ✅ Detects manual interference (user typing commands during speedwalk)
- ✅ No error message parsing needed (expected room verification works for any scenario)
- ✅ Handles both GMCP scenarios (resends same room vs. no GMCP at all)
- ✅ Auto-retries with configurable limits (prevents infinite loops)
- ✅ Works with circuit travel and auto-transit

**Key files:**
- `scripts/map_speedwalk.lua` - Verification, recovery functions, state tracking
- `triggers/speedwalk_out_of_fuel.lua` - Out of fuel detection
- `triggers/speedwalk_customs_intercept.lua` - Customs intercept detection

**Integration Pattern:**

Speedwalk communicates completion status via `F2T_SPEEDWALK_LAST_RESULT` for components that need to handle navigation outcomes.

**Result Values:**
- `"completed"` - Speedwalk reached destination successfully
- `"stopped"` - User manually stopped speedwalk (via `nav stop`)
- `"failed"` - Path blocked after max retry attempts

**Integration Example (Hauling Component):**

```lua
-- Check navigation completion
if not F2T_SPEEDWALK_ACTIVE then
    local result = F2T_SPEEDWALK_LAST_RESULT

    if result == "completed" then
        -- Verify location and continue workflow
        verify_arrival_and_proceed()

    elseif result == "stopped" then
        -- User interrupted - respect that
        cecho("\n<yellow>[component]<reset> Navigation stopped by user\n")
        stop_automation()

    elseif result == "failed" then
        -- Speedwalk couldn't get there after retries - path is blocked
        cecho("\n<red>[component]<reset> Cannot reach destination (path blocked)\n")
        handle_blocked_path()  -- Skip job, retry with different destination, etc.
    end
end
```

**Design Principle:** Components should **defer to speedwalk** for navigation decisions. If speedwalk can't reach a destination after 3 retries with path recomputation, the path is genuinely blocked. Components retrying the same navigation won't help.

**Benefits:**
- ✅ Single source of truth for navigation success/failure
- ✅ Respects user control (manual stops properly halt automation)
- ✅ Prevents infinite retry loops in calling components
- ✅ Simpler integration (no retry counters needed in components)

**See also:** `src/hauling/scripts/hauling_ac_phases.lua` for complete integration example

### 11. Room Search System

Search the map database for rooms by name/text across different scopes.

**Search Scopes:**

1. **Current Area**: `map search <text>` - Fastest, searches only the area you're in
2. **Planet/System**: `map search <location> <text>` - Searches specific planet or entire system (all planets + space)
3. **All Areas**: `map search all <text>` - Searches entire map

**How It Works:**

- Uses Mudlet's native `searchRoom()` for full-map searches (C++ optimized)
- Uses manual iteration for area-specific searches (more performant, fewer rooms to check)
- Case-insensitive substring matching
- Returns: room ID, name, Fed2 hash, system, area

**Examples:**

```lua
-- Programmatic usage:
local results = f2t_map_search_current_area("exchange")
local results = f2t_map_search_area(area_id, "landing")
local results = f2t_map_search_planet_or_system("Earth", "park")
local results = f2t_map_search_all("depot")

-- Results format:
-- {
--   {room_id = 123, name = "Exchange", hash = "Sol.Earth.45", system = "Sol", area = "Earth"},
--   ...
-- }
```

**Key Files:**
- `scripts/map_search.lua` - Search functions and display

### 12. Map Import/Export System

Export and import the entire map database for backup, sharing, or migration using Mudlet's native JSON format.

**Commands:**
- `map export` - Opens file dialog to select save location
- `map import` - Opens file dialog to select file, shows summary
- `map confirm` - Confirms and executes the import (replaces current map)
- `map cancel` - Cancels the pending import

**File Dialog:**
- Export prompts for save location with `.json` extension auto-added
- Import prompts for file selection
- User-friendly visual file selection

**Import Safety:**
- Uses shared confirmation system (same as manual mapping)
- Requires explicit `map confirm` to prevent accidental map deletion
- Shows import summary with room/area counts before confirmation
- Warning displays when importing would delete existing map
- Confirmation expires after 30 seconds (prevents stale confirmations)
- Use `map cancel` to cancel pending import
- Suggests `map export` for backup before import

**How It Works:**
- Uses Mudlet's `deleteMap()` to clear entire map before importing
- Replaces current map completely (no merge mode currently)

**What Gets Exported/Imported:**
- All rooms with Fed2 metadata (system, area, num, flags)
- All areas with Fed2 metadata (system, cartel, owner)
- Standard exits (directional connections)
- Special exits (on-arrival commands, custom exit commands)
- Room hashes (Fed2 hash → Mudlet room ID mapping)
- Room coordinates and styling

**What Doesn't Get Exported:**
- Saved destinations (`map dest`) - stored separately in settings
- Current mapper state (current room, speedwalk state)

**Use Cases:**
- **Backup**: Export before major changes or map clears
- **Sharing**: Share maps with other Fed2 players
- **Migration**: Move map between Mudlet installations

**Examples:**
```lua
-- Export map (opens file dialog)
map export

-- Import map (opens file dialog, shows summary, requires confirmation)
map import        # Opens dialog, shows import summary with room counts
map confirm       # Confirms and imports the map (replaces current)

-- Cancel import
map import        # Opens dialog, shows summary
map cancel        # Cancels the pending import

-- Typical workflow: backup before import
map export        # Backup current map first (recommended!)
map import        # Opens dialog, shows summary
map confirm       # Confirms and replaces map
```

**Technical Details:**
- Uses Mudlet's `saveJsonMap()` and `loadJsonMap()` functions (available in Mudlet 4.11.0+)
- Uses Mudlet's `deleteMap()` for safe map clearing in replace mode
- Uses `invokeFileDialog()` for user-friendly file selection (available in Mudlet 4.8+)
- Large maps show progress dialog during import automatically
- JSON format is human-readable and can be edited if needed

**Key Files:**
- `scripts/map_import_export.lua` - Export/import functions

### 13. Special Navigation System
Handles special movement requirements and auto-transit sequences using Mudlet's native special exit system with discovery-based workflow.

**On-Arrival Commands:**
- Commands executed when entering a room (before speedwalk continues)
- Stored in room user data: `fed2_arrival_cmd` (command), `fed2_arrival_type` (execution type)
- Four execution types:
  - `always`: Run every time (default)
  - `once-room`: Run once, then mark as executed (stored in `fed2_arrival_executed`)
  - `once-area`: Run once per area visit (tracked in global table, reset on area change)
  - `once-ever`: Run once ever, then mark as executed permanently
- Use cases: Pearl tabi (`wear tabi`), area permits (`buy permit` once-area), registration (`register` once-ever)
- Speedwalk waits 0.5s after execution before continuing

**Special Exits:**
- Uses Mudlet's `addSpecialExit(from_room, to_room, command)` API
- Creates actual map connections with custom commands
- Included in `getPath()` results naturally
- Two types:
  - **Custom command**: Executes special command to move (e.g., `press touchpad`)
  - **Auto-transit** (`__move_no_op_<room_id>`): Internal command that tells speedwalk to wait for GMCP without sending anything (user types `__move_no_op`, system appends room ID)
- **Discovery workflow**: Test command, auto-creates exit when room changes, supports reverse creation
- **Manual workflow**: Specify room IDs directly if known

**Discovery-Based Workflow (RECOMMENDED):**
```lua
-- 1. At source room, test command:
map exit special press touchpad
-- Command sent, system waits for room change
-- On room change: exit auto-created from source to destination

-- 2. Create reverse exit immediately:
map exit special reverse
-- Creates exit from current room back to source using same command

-- For auto-transit rooms:
map exit special noop
-- No command sent, waits for GMCP
map exit special reverse
-- Creates reverse auto-transit

-- Override reverse command if different:
map exit special reverse press red button
```

**Manual Workflow (if room IDs known):**
```lua
-- From current room to room 1235:
map exit special 1235 press touchpad

-- From room 1235 to 1236:
map exit special 1235 1236 noop
```

**Auto-Transit Handling:**
- For multi-room automatic sequences (e.g., airlock: Room A → press touchpad → Room B → auto → Room C)
- Room A → Room B: Special exit with command `press touchpad`
- Room B → Room C: User creates with `__move_no_op`, stored as `__move_no_op_<dest_room_id>`
- Speedwalk recognizes `__move_no_op_*` pattern in path and waits for GMCP room change
- Handles any number of automatic transitions
- Room ID suffix allows multiple auto-transits from same room to different destinations

**How It Works:**

1. **Discovery-Based Exit Creation:**
   - User runs `map exit special <command>` at source room
   - System stores pending discovery state: source room ID, command
   - System sends the command (unless `__move_no_op`)
   - On GMCP room change: System auto-creates exit, stores last discovery for reverse
   - User can immediately run `map exit special reverse` to create return path

2. **Pathfinding:**
   - `getPath(from, to)` includes special exits in calculated path
   - Path may contain: normal directions ("north", "east") OR special commands ("press touchpad", "__move_no_op_<id>")

3. **Speedwalk Execution:**
   - For each step in path:
     - If step starts with "__move_no_op": Wait for next GMCP room change (don't send anything)
     - Otherwise: Send the step (normal direction or special command)
   - On GMCP room change:
     - Check for on-arrival command and execution type
     - Execute if should run (based on type and execution history)
     - Mark as executed if needed
     - Wait 0.5s if on-arrival executed
     - Continue to next speedwalk step

4. **Example Path:**
   ```
   ["north", "east", "press touchpad", "__move_no_op", "south"]
   ```
   - Steps 1-2: Normal directions
   - Step 3: Special command
   - Step 4: Auto-transit (wait for GMCP)
   - Step 5: Normal direction

## Implementation Patterns

### Movement Commands: Always Use Speedwalk Pattern

**CRITICAL: Never use `send()` directly for movement commands. Always use the speedwalk pattern.**

**Why:** The speedwalk pattern provides essential protections:
- **Timeout detection**: Detects when movement gets stuck (no GMCP response)
- **Automatic retry**: Recomputes path and retries on failure
- **Failure tracking**: Counts failures and stops after max retries
- **State integration**: Works with circuit travel, auto-transit, and other navigation systems

**Pattern:**
```lua
-- ✅ CORRECT: Use speedwalk pattern
speedWalkDir = {string.format("jump %s", system_name)}
speedWalkPath = {nil}  -- Blind movement (destination unknown)
doSpeedWalk()

-- ❌ INCORRECT: Direct send
send(string.format("jump %s", system_name))
```

**When to use:**
- Any command that causes room change (jump, board, exit, special commands)
- Blind movement (destination not in map database)
- Commands that might fail and need retry

**Blind movement setup:**
```lua
speedWalkDir = {command}  -- Command to send
speedWalkPath = {nil}     -- nil = blind movement
doSpeedWalk()
```

**Multiple commands:**
```lua
speedWalkDir = {"command1", "command2", "command3"}
speedWalkPath = {nil, nil, nil}  -- All blind
doSpeedWalk()
```

**See also:**
- Section 10: Speedwalk Movement Verification and Auto-Recovery
- `src/map/scripts/map_speedwalk.lua` - Speedwalk implementation
- `src/map/scripts/map_explore_cartel.lua:255` - Example usage for jump commands

### Circuit Movement Pattern (Event-Driven State Machine)

**Location:** `scripts/map_circuit.lua`, `triggers/map_circuit_*.lua`

The circuit movement system is the **reference implementation** for event-driven state machine patterns using `tempRegexTrigger()` and `tempTimer()`.

**Use this as a template for:** Train/tube navigation, any multi-phase automation with unpredictable timing

#### Why tempRegexTrigger Instead of Permanent Triggers?

**Problem:** Circuit travel is unpredictable and infrequent:
- Each circuit stop has a unique arrival message pattern
- May wait seconds or minutes for vehicle arrival
- Runs infrequently (user command)
- Don't want triggers firing when not circuit traveling

**Solution:** Create triggers dynamically only when needed, kill them when done.

**Benefits:**
1. **Zero interference when inactive** - triggers don't exist until circuit travel starts
2. **Dynamic patterns** - each stop can have unique announcement pattern
3. **Lifecycle safety** - triggers die when workflow completes
4. **Memory efficiency** - no permanent overhead for rare operation
5. **State coupling** - trigger lifecycle matches workflow lifecycle

#### Architecture Overview

```lua
-- Global state with trigger ID tracking
F2T_MAP_CIRCUIT_STATE = {
    active = false,
    phase = nil,  -- "waiting_arrival" or "waiting_destination"

    -- Circuit data
    circuit_id = nil,
    destination_stop = nil,
    destination_room = nil,
    board_command = nil,
    exit_command = nil,

    -- Trigger IDs for cleanup
    boarding_trigger_id = nil,
    arrival_trigger_id = nil
}
```

#### Progressive Trigger Creation

**Key principle:** Don't create all triggers at start. Create them phase-by-phase as needed.

```lua
-- Phase 1: Start with boarding trigger only
function f2t_map_circuit_begin(circuit_command)
    F2T_MAP_CIRCUIT_STATE.active = true
    F2T_MAP_CIRCUIT_STATE.phase = "waiting_arrival"
    -- ... initialize other fields ...

    -- Create boarding trigger
    f2t_map_circuit_create_boarding_trigger()
end

-- Phase 2: Create arrival trigger AFTER boarding
function f2t_map_circuit_handle_boarding()
    -- Kill boarding trigger immediately
    killTrigger(F2T_MAP_CIRCUIT_STATE.boarding_trigger_id)
    F2T_MAP_CIRCUIT_STATE.boarding_trigger_id = nil

    send(F2T_MAP_CIRCUIT_STATE.board_command)
    F2T_MAP_CIRCUIT_STATE.phase = "waiting_destination"

    -- Wait 0.5s before creating arrival trigger (avoid race conditions)
    tempTimer(0.5, function()
        if F2T_MAP_CIRCUIT_STATE.active and F2T_MAP_CIRCUIT_STATE.phase == "waiting_destination" then
            f2t_map_circuit_create_arrival_trigger()
        end
    end)
end
```

**Why wait 0.5s?**
- Game outputs boarding announcement text line-by-line
- Arrival trigger pattern might match boarding text if created immediately
- Delay ensures all boarding text has arrived before arrival trigger exists

#### State-Driven Guards

Every handler checks state before doing anything:

```lua
function f2t_map_circuit_handle_boarding(skip_send)
    -- Guard #1: System active
    if not F2T_MAP_CIRCUIT_STATE.active then
        return
    end

    -- Guard #2: Correct phase
    if F2T_MAP_CIRCUIT_STATE.phase ~= "waiting_arrival" then
        return
    end

    -- Safe to proceed
    -- ...
end
```

**Why guards?**
- Prevents double-firing if trigger fires twice
- Prevents arrival handler from running during boarding phase
- Allows manual stop (setting active=false stops all handlers)
- Makes debugging easier (can inspect state at any point)

#### Immediate Trigger Cleanup

**Critical pattern:** Kill triggers as soon as they fire (don't wait for workflow completion)

```lua
function f2t_map_circuit_handle_boarding()
    // Guard checks...

    // Kill trigger FIRST
    if F2T_MAP_CIRCUIT_STATE.boarding_trigger_id then
        killTrigger(F2T_MAP_CIRCUIT_STATE.boarding_trigger_id)
        F2T_MAP_CIRCUIT_STATE.boarding_trigger_id = nil
    end

    // Then do work
    send(F2T_MAP_CIRCUIT_STATE.board_command)
    // ...
end
```

**Why kill immediately?**
- Prevents trigger from firing again
- Frees memory sooner
- Clearer lifecycle (trigger exists only while waiting for its event)

#### Cleanup on All Exit Paths

```lua
function f2t_map_circuit_delete_triggers()
    if F2T_MAP_CIRCUIT_STATE.boarding_trigger_id then
        killTrigger(F2T_MAP_CIRCUIT_STATE.boarding_trigger_id)
        F2T_MAP_CIRCUIT_STATE.boarding_trigger_id = nil
    end
    if F2T_MAP_CIRCUIT_STATE.arrival_trigger_id then
        killTrigger(F2T_MAP_CIRCUIT_STATE.arrival_trigger_id)
        F2T_MAP_CIRCUIT_STATE.arrival_trigger_id = nil
    end
end

// Success path
function f2t_map_circuit_verify_and_resume() {
    f2t_map_circuit_delete_triggers()
    F2T_MAP_CIRCUIT_STATE = {active = false}
    f2t_map_speedwalk_on_room_change()  // Continue
}

// Error path
function f2t_map_circuit_verify_and_resume() {
    f2t_map_circuit_delete_triggers()
    F2T_MAP_CIRCUIT_STATE = {active = false}
    f2t_map_speedwalk_stop()  // Abort
}

// Manual stop
function f2t_map_circuit_stop() {
    f2t_map_circuit_delete_triggers()
    F2T_MAP_CIRCUIT_STATE = {active = false}
    f2t_map_speedwalk_stop()
}
```

#### Complete Lifecycle Flow

```
1. START: f2t_map_circuit_begin(circuit_command)
   ├─ Parse circuit data from map
   ├─ Initialize F2T_MAP_CIRCUIT_STATE
   ├─ Set phase = "waiting_arrival"
   └─ Create boarding trigger (tempRegexTrigger)

2. WAIT: Boarding trigger listening for vehicle announcement
   └─ Game sends: "The shuttle bus announces its arrival"

3. BOARDING: Trigger fires → f2t_map_circuit_handle_boarding()
   ├─ Guard: Check active and phase
   ├─ Kill boarding trigger (no longer needed)
   ├─ Send board command
   ├─ Set phase = "waiting_destination"
   └─ tempTimer(0.5s) → Create arrival trigger

4. WAIT: Arrival trigger listening for destination announcement
   └─ Game sends: "The shuttle bus has arrived at Exchange"

5. ARRIVAL: Trigger fires → f2t_map_circuit_handle_arrival()
   ├─ Guard: Check active and phase
   ├─ Kill arrival trigger immediately
   ├─ Send exit command
   └─ tempTimer(0.5s) → Verify and resume

6. VERIFY: f2t_map_circuit_verify_and_resume()
   ├─ Check if current_room == destination_room
   ├─ SUCCESS:
   │  ├─ Delete any remaining triggers
   │  ├─ Clear state (active = false)
   │  └─ Resume speedwalk
   └─ FAILURE:
      ├─ Delete triggers
      ├─ Clear state
      └─ Stop speedwalk

7. END: Circuit complete, state cleared, all triggers killed
```

#### Why This Pattern Works

**For circuit movement specifically:**
- **Unpredictable timing**: May wait 2 seconds or 2 minutes for vehicle
- **Dynamic patterns**: Each circuit stop has unique destination name
- **Infrequent**: User command, not run in tight loops
- **Multi-phase**: Boarding → traveling → arrival (can't be single trigger)

**General applicability:**
- Any workflow with multiple unpredictable wait points
- Workflows where patterns vary per invocation
- Complex state machines with cleanup requirements
- Operations run infrequently (creation overhead acceptable)

#### When NOT to Use This Pattern

❌ **Data capture** (factory status, price check):
- Runs frequently → creation overhead matters
- Known patterns → can use permanent triggers
- Simple lifecycle → start, capture, complete

❌ **Simple state tracking** (room changes):
- GMCP event handlers are simpler
- No pattern matching needed
- No cleanup required

**See Also:**
- `CLAUDE.md` - Pattern selection guidelines
- `CLAUDE_PATTERNS.md` - Event-driven state machine pattern template
- `src/map/scripts/map_circuit.lua` - Complete implementation

## Key Files

**Scripts:**
- `init.lua` - Initialization, mapper registration, settings
- `map_core.lua` - GMCP event handler, on-arrival command execution
- `map_room.lua` - Auto-mapping room creation logic
- `map_room_query.lua` - Room query utilities (flags, location checks)
- `map_area.lua` - Area management, system space helpers, location parsing
- `map_helpers.lua` - GMCP wrappers and map lookup helpers (planet/system lookups, current location)
- `map_exit.lua` - Exit handling (standard + special)
- `map_jump.lua` - Jump exit auto-discovery
- `map_special.lua` - Special navigation (on-arrival commands, special exit API)
- `map_coords.lua` - Coordinate calculation
- `map_style.lua` - Room styling
- `map_navigate.lua` - Navigation resolution
- `map_speedwalk.lua` - Speedwalk control, __move_no_op keyword handling, interruption recovery
- `map_destinations.lua` - Saved destinations
- `map_search.lua` - Room search by name/text
- `map_import_export.lua` - Map import/export functionality
- `map_manual_confirm.lua` - Confirmation system for destructive operations
- `map_manual_room.lua` - Manual room creation, deletion, property editing
- `map_manual_exit.lua` - Manual exit add/remove, listing
- `map_manual_lock.lua` - Room/exit locking for navigation control
- `map_manual_stub.lua` - Stub exit creation, deletion, connection, listing
- `map_raw.lua` - Raw data display for diagnostics (mapper and GMCP data)
- `map_help_init.lua` - Help registry initialization

**Triggers:**
- `jump_capture_start.lua` - Detect jump output headers (Inter-Cartel and Local)
- `jump_capture_line.lua` - Capture indented destination lines
- `speedwalk_out_of_fuel.lua` - Detect and recover from out-of-fuel interruption
- `speedwalk_customs_intercept.lua` - Detect and recover from Sol customs intercept

**Aliases:**
- `nav.lua` - Navigation (consolidated alias)
- `map_*.lua` - Map subcommands
- `map.lua` - Main map command (includes special navigation)

## Critical Implementation Patterns

### 1. GMCP as Authoritative Source

**ALWAYS** use `gmcp.room.info` first, fall back to stored data only if unavailable:

```lua
-- ✅ CORRECT
local system = gmcp.room and gmcp.room.info and gmcp.room.info.system
if not system then
    system = getRoomUserData(room_id, "fed2_system")
end

-- ❌ INCORRECT
local system = getRoomUserData(room_id, "fed2_system")  -- Stale data
```

**Why:** GMCP is always current, stored data may be stale or incomplete.

### 2. Hash Format

Fed2 hash: `system.area.num` (delimiter: period)
- Example: `Coffee.Latte.459`
- All components required
- Case-sensitive

### 3. Room ID Management

- Use `createRoomID()` for new rooms (never manual IDs)
- Store hash→ID mapping immediately
- Always check hash existence before creating room

### 4. Map UI Focus

After creating special exits/stubs, call `centerview(current_room_id)` to restore focus.

### 5. Stub Room Pattern

For unmapped jump destinations:
1. Create stub area: `{System} Space`
2. Create stub room: `{system}.{system} Space.0`
3. Set `fed2_stub = "true"` user data
4. Update when visited with real data

### 6. Y-Axis Inversion

Mudlet: +y is south (down)
Fed2: +y is south (down from top-left)
Solution: Multiply y-offset by -1

### 7. Checking Room Flags

**ALWAYS use the helper function** instead of direct user data access:

```lua
-- ✅ CORRECT: Use helper function
if f2t_map_room_has_flag(room_id, "link") then
    -- Room has link flag
end

-- ❌ INCORRECT: Direct access
local has_flag = getRoomUserData(room_id, "fed2_flag_link")
if has_flag == "true" then
    -- Works but not consistent with codebase patterns
end
```

**Why:** Flags are stored as individual user data fields (`fed2_flag_link`, `fed2_flag_shuttlepad`, etc.), not as a single `fed2_flags` field. The helper function encapsulates this pattern.

**Available in:** `src/map/scripts/map_room_query.lua`

**Related functions:**
- `f2t_map_find_room_with_flag(area_id, flag)` - Find first room with flag in area
- `f2t_map_find_all_rooms_with_flag(area_id, flag)` - Find all rooms with flag in area

### 8. Already-at-Destination Pattern

**When calling `f2t_map_navigate()` and expecting to handle arrival in a room change event, always check if already at destination:**

```lua
-- Navigate to destination
local success = f2t_map_navigate(destination)
if not success then
    handle_navigation_error()
    return
end

-- Check if already at destination (no room change will fire)
if F2T_MAP_CURRENT_ROOM_ID == expected_destination_room_id then
    -- Already here, proceed immediately (don't wait for room change)
    handle_arrival_immediately()
else
    -- Navigation in progress, room change event will handle arrival
end
```

**Why:** `f2t_map_navigate()` returns success even when already at destination, but doesn't trigger a room change event. Code waiting for room change will hang forever.

**Examples:**
- `map_explore_cartel.lua:241` - Check if already at link before jumping
- `map_explore_system.lua:453` - Check if already at orbit before boarding

## Settings

See `src/shared/CLAUDE.md` for settings system documentation.

**Registered Settings:**
- `enabled` (boolean, default: true) - Enable/disable auto-mapping
- `planet_nav_default` (string, default: "shuttlepad") - Default for `nav <planet>`
- `speedwalk_timeout` (number, default: 3, range: 1-10) - Timeout in seconds to wait for movement (detects stuck speedwalk)
- `speedwalk_max_retries` (number, default: 3, range: 1-10) - Maximum retry attempts before stopping speedwalk
- `map_manual_confirm` (boolean, default: true) - Require confirmation for destructive manual mapping operations
- `orbit_planet_initial` (boolean, default: false) - Use first letter of planet name as orbit room label instead of 'O' (updates as you explore; rooms visited before enabling will show 'O' until re-visited)

**Complex Settings (direct access):**
- `destinations` - Saved destination table

## Debug Logging

```
f2t debug on
```

Debug messages:
- `[map] Room created: <hash> -> ID <id>`
- `[map] Area created: <name>`
- `[map] Exit added: <from> -> <to> (<dir>)`
- `[map] Coordinates set: (<x>, <y>, <z>)`

## Troubleshooting

**Map not updating:** Check `F2T_MAP_ENABLED` (`map on`)
**Rooms in wrong positions:** Check y-axis inversion
**Exits not connecting:** Verify GMCP `exits` format
**Duplicate rooms:** Check hash generation (GMCP inconsistency)

## Future Enhancements

- Manual room editing (adjust positions, merge duplicates)
- Room notes
- ~~Search by name/flag~~ ✓ Implemented
- ~~Auto-jump parsing on link room entry~~ ✓ Implemented
- ~~Map sharing (export/import)~~ ✓ Implemented
