-- ==============================================================================
-- DCS-CAI LUA API REFERENCE DICTIONARY
-- ==============================================================================

-- Function: Airbase.getWarehouse
-- Doc: Returns the Warehouse object associated with the Airbase for logistics management.
function Airbase.getWarehouse(airbase_object) end

-- Function: Warehouse.getInventory
-- Doc: Returns the complete inventory of the warehouse, including weapons, fuel, and liquids. EXCLUSIVELY use this for resource and storage handling.
function Warehouse.getInventory(warehouse_object) end

-- Function: world.VolumeType
-- Doc: Enum for volume types. Includes world.VolumeType.SPHERE and world.VolumeType.BOX.
world.VolumeType = {} 

-- Function: world.searchObjects
-- Doc: NATIVE, high-performance API to search for objects within a specified volume. MUST be used instead of calculating distances manually to preserve server framerate.
-- Parameters: (category, volume, handler).
-- 'volume' is a table: {id = world.VolumeType.SPHERE, params = {point = {x,y,z}, radius = n}} OR {id = world.VolumeType.BOX, params = {min = {x,y,z}, max = {x,y,z}}}.
-- 'handler' is a callback function (function(obj, val) ... return true end).
function world.searchObjects(category, volume, handler) end

-- ==============================================================================
-- EVENT-DRIVEN ARCHITECTURE (Core Engine)
-- ==============================================================================

-- Function: world.addEventHandler
-- Doc: Registers a global listener for game events (e.g., SHOT, KILL, HIT, BIRTH). Crucial for sending telemetry out to the middleware without using heavy polling loops.
-- Parameters: (handler) where 'handler' is a table containing an 'onEvent(event)' function.
function world.addEventHandler(handler) end

-- Function: world.removeEventHandler
-- Doc: Removes a previously registered event handler. Useful for memory cleanup during script de-initialization or restarts.
-- Parameters: (handler) the exact table instance passed during the add phase.
function world.removeEventHandler(handler) end

-- Function: world.onEvent
-- Doc: Internal engine trigger method used to propagate the event. Generally not called manually, but exploited via addEventHandler.
function world.onEvent(event) end

-- ==============================================================================
-- SITUATIONAL AWARENESS & HMI (Human-Machine Interface)
-- ==============================================================================

-- Function: world.getAirbases
-- Doc: Returns an array containing all active airbases, FARPs, and ships with flight decks on the current map.
-- Parameters: (coalition) optional, e.g., coalition.side.RED or coalition.side.BLUE. If omitted, returns all.
function world.getAirbases(coalition) end

-- Function: world.getPlayer
-- Doc: Returns the Unit object associated with the local player. Useful in client-side scripts, but strictly not recommended for server-side logic in multiplayer environments.
function world.getPlayer() end

-- Function: world.getMarkPanels
-- Doc: Retrieves all markers drawn on the F10 tactical map. Acts as the primary Human-Machine Interface (HMI) for issuing C2 orders by reading text and physical coordinates.
-- Parameters: (coalition) optional, used to restrict the query to a specific faction's markers.
function world.getMarkPanels(coalition) end

-- ==============================================================================
-- STATE & PERSISTENCE (Data Logging)
-- ==============================================================================

-- Function: world.getPersistenceData
-- Doc: Extracts the current state of static objects, destroyed buildings, and craters. Useful for logging state to an external database (e.g., TimescaleDB) to rebuild the map state.
function world.getPersistenceData() end

-- Function: world.setPersistenceHandler
-- Doc: Hooks a custom function to handle persistent data saving when requested by the core DCS engine.
function world.setPersistenceHandler(handler) end

-- Function: world.runPersistenceHandlers
-- Doc: Forces execution of all registered persistence modules. Typically called right before a scheduled server shutdown.
function world.runPersistenceHandlers() end

-- Function: world.setPersistencePassthrough
-- Doc: Enables or disables the passthrough of persistence data to the core engine.
function world.setPersistencePassthrough(isEnabled) end

-- Function: world.removeJunk
-- Doc: Cleans up the game world (e.g., wreckages, debris, parachutes). Highly useful for manual garbage collection in long-running Dynamic Campaigns.
-- Parameters: (volume) optional, to restrict cleanup to a specific area.
function world.removeJunk(volume) end
-- Function: world.event
-- Doc: Enum for all DCS World events. 
-- CRITICAL RULES: 
-- 1. Always use exact names: world.event.S_EVENT_SHOT (value 1), world.event.S_EVENT_HIT (value 2), world.event.S_EVENT_KILL (value 28), world.event.S_EVENT_DEAD (value 8).
-- 2. When doing UDP Networking, NEVER create and close sockets inside the event handler. Initialize the socket globally ONCE at the top of the file, set timeout to 0 (non-blocking), and reuse it inside the handler to prevent severe lag.
-- 3. NEVER use require("json"). Always build JSON packets manually using string.format.
function world.event() end
-- Function: socket
-- Doc: Standard Lua socket library available in DCS. ALWAYS use this for UDP/TCP instead of io.popen or netcat.
-- Example: local s = require("socket"); local udp = s.udp(); udp:settimeout(0); udp:setpeername("192.168.0.25", 5000); udp:send(data)
function socket() end