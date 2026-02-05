--[[
    Forza Horizon-Style DUI Navigation System
    
    Uses ox_lib's DUI helper for clean texture management
    Renders arrows using DrawSprite at world positions projected to screen
    
    REQUIRES: ox_lib
]]

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local Config = {
    -- Lane settings
    MaxArrows = 15,                    -- Maximum lane segments visible
    MinDistance = 3.0,                 -- Minimum distance from player (meters)
    MaxDistance = 50.0,                -- Maximum distance from player (meters)
    ArrowSpacing = 3.0,                -- Distance between lane segments (meters) - closer for continuous look
    
    -- Visual settings
    ArrowSize = 0.10,                  -- Base width of lane segment (wider)
    ArrowHeight = 0.22,                -- Height of lane segment (longer)
    GroundOffset = 0.05,               -- Height above ground (meters) - very low for flat on road
    FadeStartDist = 35.0,              -- Distance where fade begins
    FadeEndDist = 50.0,                -- Distance where fully faded
    
    -- DUI settings
    DuiWidth = 256,                    -- DUI texture width
    DuiHeight = 256,                   -- DUI texture height
    
    -- Update intervals
    UpdateInterval = 0,                -- Arrow render (0 = every frame for smooth)
    NavCheckInterval = 250,            -- Navigation check interval (ms) - match the example
    
    -- Turn curve settings (degrees per arrow for curves)
    GradualTurnAngle = 8.0,            -- For normal left/right turns
    SharpTurnAngle = 15.0,             -- For sharp turns
}

-- ============================================================================
-- STATE VARIABLES
-- ============================================================================

local dui = nil                        -- ox_lib DUI object
local arrowPositions = {}              -- Calculated arrow world positions
local currentDirection = -1            -- Current navigation direction
local lastDirection = -1               -- Previous direction (to detect changes)
local isNavigating = false             -- Whether we have an active waypoint
local isFrozen = false                 -- Whether arrows are frozen during recalc
local waypointCoords = nil             -- Current waypoint coordinates
local systemReady = false              -- Whether DUI is initialized

-- Direction constants
local DIR_LEFT = 3
local DIR_RIGHT = 4
local DIR_STRAIGHT = 5
local DIR_SHARP_LEFT = 6
local DIR_SHARP_RIGHT = 7

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get ground Z coordinate at a position using raycast
--- @param x number X coordinate
--- @param y number Y coordinate
--- @param z number Starting Z coordinate
--- @return number|nil Ground Z coordinate or nil if not found
local function GetGroundZ(x, y, z)
    local startZ = z + 10.0
    local endZ = z - 10.0
    
    local ray = StartShapeTestRay(x, y, startZ, x, y, endZ, 1 + 16, PlayerPedId(), 0)
    local _, hit, hitCoords = GetShapeTestResult(ray)
    
    if hit then
        return hitCoords.z
    end
    
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
    if found then
        return groundZ
    end
    
    return nil
end

--- Calculate alpha based on distance (for fade effect)
--- @param distance number Distance from player
--- @return number Alpha value (0.0-1.0)
local function CalculateAlpha(distance)
    if distance <= Config.FadeStartDist then
        return 1.0
    elseif distance >= Config.FadeEndDist then
        return 0.0
    else
        local fadeRange = Config.FadeEndDist - Config.FadeStartDist
        local fadeProgress = (distance - Config.FadeStartDist) / fadeRange
        return 1.0 - fadeProgress
    end
end

--- Get the waypoint blip coordinates if set
--- @return vector3|nil Waypoint coordinates or nil
local function GetWaypointCoords()
    local blip = GetFirstBlipInfoId(8) -- Waypoint blip
    
    if not DoesBlipExist(blip) then
        return nil
    end
    
    local coords = GetBlipInfoIdCoord(blip)
    
    local groundZ = GetGroundZ(coords.x, coords.y, coords.z)
    if groundZ then
        coords = vector3(coords.x, coords.y, groundZ)
    end
    
    return coords
end

--- Check if a direction value is valid for our system
--- @param direction number Direction value
--- @return boolean
local function IsValidDirection(direction)
    -- Direction values from GenerateDirectionsToCoord:
    -- 0 = no turn / unknown (treat as straight)
    -- 1 = left?
    -- 2 = right?
    -- 3 = turn left
    -- 4 = turn right
    -- 5 = keep straight
    -- 6 = sharp left
    -- 7 = sharp right
    -- Accept 0-7 as valid
    return direction ~= nil and direction >= 0 and direction <= 7
end

--- Get the turn angle based on direction value
--- @param direction number Direction from GenerateDirectionsToCoord
--- @return number Angle adjustment in degrees
local function GetDirectionAngle(direction)
    -- Direction values:
    -- 1 = wrong way (u-turn)
    -- 3 = left turn
    -- 4 = right turn  
    -- 5 = straight
    -- 6 = sharp left
    -- 7 = sharp right
    
    if direction == 1 then
        return 180.0  -- U-turn
    elseif direction == 3 then
        return 30.0   -- Left turn
    elseif direction == 4 then
        return -30.0  -- Right turn
    elseif direction == 6 then
        return 50.0   -- Sharp left
    elseif direction == 7 then
        return -50.0  -- Sharp right
    end
    
    return 0.0  -- Straight (direction 5 or others)
end

--- Get closest vehicle node and its heading at a position
--- @param pos vector3 Position to check
--- @return vector3|nil nodePos, number|nil heading
local function GetClosestNodeAtPos(pos)
    local found, nodePos, heading = GetClosestVehicleNodeWithHeading(pos.x, pos.y, pos.z, 1, 3.0, 0)
    if found then
        return nodePos, heading
    end
    return nil, nil
end

--- Draw 3D text at a world position
--- @param x number X coordinate
--- @param y number Y coordinate  
--- @param z number Z coordinate
--- @param text string Text to display
local function DrawText3D(x, y, z, text)
    local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(0.4, 0.4)
        SetTextFont(4)
        SetTextProportional(true)
        SetTextColour(0, 255, 255, 255)
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(true)
        AddTextComponentString(text)
        DrawText(screenX, screenY)
    end
end

--- Get direction name for debug
--- @param dir number Direction value
--- @return string Direction name
local function GetDirectionName(dir)
    local names = {
        [0] = "CALC",
        [1] = "WRONG_WAY",
        [2] = "UNK_2",
        [3] = "LEFT",
        [4] = "RIGHT",
        [5] = "STRAIGHT",
        [6] = "SHARP_L",
        [7] = "SHARP_R",
        [8] = "RECALC"
    }
    return names[dir] or "UNKNOWN"
end

--- Calculate positions for all arrows by following road nodes
--- @param playerPos vector3 Player position
--- @param playerHeading number Player heading
--- @param initialDirection number Initial navigation direction
--- @param distToTurn number Distance to next turn in meters
local function CalculateArrowPositions(playerPos, playerHeading, initialDirection, distToTurn)
    arrowPositions = {}
    
    if isFrozen then
        return
    end
    
    if not IsValidDirection(initialDirection) then
        return
    end
    
    -- Get waypoint destination
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        return
    end
    
    -- Start from player position and heading - DO NOT snap to road node heading
    -- Just use player's actual heading
    local currentPos = vector3(playerPos.x, playerPos.y, playerPos.z)
    local currentHeading = playerHeading
    
    -- If wrong way, flip direction
    if initialDirection == 1 then
        currentHeading = playerHeading + 180.0
    end
    
    -- Get the turn angle for current direction
    local turnAngle = GetDirectionAngle(initialDirection)
    
    -- Only apply turn curve if we're close to the turn (within arrow range)
    -- If turn is far away (distToTurn > MaxDistance), go straight
    if distToTurn > Config.MaxDistance then
        turnAngle = 0.0  -- Go straight, turn is too far
    end
    
    -- Calculate how much to turn per arrow to spread the turn
    local turnPerArrow = turnAngle / Config.MaxArrows
    
    for i = 1, Config.MaxArrows do
        local stepDistance = Config.ArrowSpacing
        if i == 1 then
            stepDistance = Config.MinDistance
        end
        
        -- Calculate cumulative distance from player
        local cumulativeDist = Config.MinDistance + ((i - 1) * Config.ArrowSpacing)
        
        -- Only start turning when we're near the turn point
        local applyTurn = 0.0
        if distToTurn <= Config.MaxDistance and cumulativeDist >= (distToTurn - 10.0) then
            -- Start curving when we're within 10m of the turn
            applyTurn = turnPerArrow
        end
        
        -- Apply gradual turn
        currentHeading = currentHeading + applyTurn
        
        -- Step forward from current position
        local radians = math.rad(currentHeading)
        local offsetX = -math.sin(radians) * stepDistance
        local offsetY = math.cos(radians) * stepDistance
        
        local nextX = currentPos.x + offsetX
        local nextY = currentPos.y + offsetY
        local nextZ = currentPos.z
        
        -- Try to snap to road height
        local roadNode = GetClosestNodeAtPos(vector3(nextX, nextY, nextZ))
        if roadNode then
            nextZ = roadNode.z
        end
        
        -- Calculate distance from player
        local distFromPlayer = #(vector3(nextX, nextY, nextZ) - playerPos)
        
        if distFromPlayer <= Config.MaxDistance then
            local alpha = CalculateAlpha(distFromPlayer)
            
            table.insert(arrowPositions, {
                pos = vector3(nextX, nextY, nextZ + Config.GroundOffset),
                heading = currentHeading,
                alpha = alpha,
                distance = distFromPlayer
            })
            
            currentPos = vector3(nextX, nextY, nextZ)
        end
    end
end

-- ============================================================================
-- DUI INITIALIZATION (using ox_lib)
-- ============================================================================

--- Initialize the DUI using ox_lib's helper
local function InitializeDUI()
    local duiUrl = ("nui://%s/dui/arrow.html"):format(GetCurrentResourceName())
    
    print("^3[NavArrows] Creating DUI with URL: " .. duiUrl .. "^0")
    
    -- Create DUI using ox_lib helper
    dui = lib.dui:new({
        url = duiUrl,
        width = Config.DuiWidth,
        height = Config.DuiHeight,
        debug = true
    })
    
    if not dui then
        print("^1[NavArrows] Failed to create DUI object^0")
        return false
    end
    
    Wait(500)
    
    print("^2[NavArrows] DUI created successfully^0")
    print("^2[NavArrows] Texture Dict: " .. tostring(dui.dictName) .. "^0")
    print("^2[NavArrows] Texture Name: " .. tostring(dui.txtName) .. "^0")
    
    systemReady = true
    return true
end

--- Clean up DUI resources
local function CleanupDUI()
    if dui then
        dui:remove()
        dui = nil
    end
    systemReady = false
    print("^3[NavArrows] DUI cleaned up^0")
end

-- ============================================================================
-- NAVIGATION LOGIC
-- ============================================================================

--- Get navigation direction to waypoint using GenerateDirectionsToCoord
--- @return number direction, number distance
local function GetNavigationDirection()
    if not IsWaypointActive() then
        return -1, 0
    end
    
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        return -1, 0
    end
    
    local dest = GetBlipInfoIdCoord(blip)
    waypointCoords = dest
    
    local retval, direction, vehicle, dist = GenerateDirectionsToCoord(dest.x, dest.y, dest.z, true)
    -- Distance returned is to the next turn point, in some unit (seems like decimeters)
    local distMeters = (dist or 0) / 10.0
    
    return direction or 0, distMeters
end

-- Store distance to turn globally for debug display
local distanceToTurn = 0

-- ============================================================================
-- ARROW RENDERING
-- ============================================================================
local function DrawArrows()
    if not systemReady then
        return
    end
    
    if not dui then
        return
    end
    
    if #arrowPositions == 0 then
        return
    end
    
    -- Get camera rotation for proper sprite orientation
    local camRot = GetFinalRenderedCamRot(2)
    local camHeading = camRot.z
    local camPitch = camRot.x  -- Pitch angle (looking down = negative)
    
    -- Calculate how much to squash the sprite based on camera pitch
    -- When looking straight down (-90), sprite should be nearly flat
    -- When looking horizontal (0), sprite is more vertical
    local pitchFactor = math.abs(camPitch) / 90.0  -- 0 to 1 based on how much we're looking down
    pitchFactor = math.max(0.15, math.min(1.0, pitchFactor))  -- Clamp between 0.15 and 1.0
    
    for _, arrow in ipairs(arrowPositions) do
        local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(
            arrow.pos.x, 
            arrow.pos.y, 
            arrow.pos.z
        )
        
        if onScreen then
            -- Size based on distance (closer = larger, further = smaller)
            local sizeFactor = 1.0 - (arrow.distance / Config.MaxDistance) * 0.4
            local width = Config.ArrowSize * sizeFactor
            -- Squash height based on camera pitch to simulate laying flat
            local height = Config.ArrowHeight * sizeFactor * pitchFactor
            
            -- Rotation: keep lane fixed in world space, not rotating with camera
            -- Arrow heading is world direction, we need to show it relative to camera view
            local spriteRotation = arrow.heading - camHeading
            
            -- Color: change based on distance to turn
            -- Green (default) -> Yellow (< 20m) -> Red (< 10m)
            local r, g, b = 0, 255, 100  -- Default green
            
            -- Check if there's a turn coming (any direction except straight)
            local isTurnComing = (currentDirection == 1 or currentDirection == 3 or currentDirection == 4 or currentDirection == 6 or currentDirection == 7)
            
            if isTurnComing and distanceToTurn > 0 then
                if distanceToTurn < 10.0 then
                    -- Red when very close (< 10m)
                    r, g, b = 255, 50, 50
                elseif distanceToTurn < 30.0 then
                    -- Yellow when approaching (10-20m)
                    r, g, b = 255, 200, 0
                end
                -- Otherwise stays green (> 20m)
            end
            
            -- Draw the lane segment sprite
            DrawSprite(
                dui.dictName,
                dui.txtName,
                screenX,
                screenY,
                width,
                height,
                spriteRotation,
                r, g, b,
                math.floor(arrow.alpha * 200)
            )
        end
    end
end

-- ============================================================================
-- MAIN THREADS
-- ============================================================================

--- Navigation check thread (lower frequency)
CreateThread(function()
    -- Wait for system to be ready
    while not systemReady do
        Wait(100)
    end
    
    while true do
        Wait(Config.NavCheckInterval)
        
        if IsWaypointActive() then
            isNavigating = true
            
            -- Get direction from GenerateDirectionsToCoord
            local direction, dist = GetNavigationDirection()
            distanceToTurn = dist  -- Store for debug display
            
            -- DEBUG: Print to console
            print(("^3[NavArrows] DIR: %d (%s) | DIST TO TURN: %.1f m | Valid: %s^0"):format(
                direction or -1,
                GetDirectionName(direction),
                dist or 0,
                tostring(IsValidDirection(direction))
            ))
            
            -- Update direction (even if 0, treat as straight for now)
            if direction ~= lastDirection then
                currentDirection = direction
                lastDirection = direction
                
                isFrozen = true
                Wait(50)
                isFrozen = false
            else
                currentDirection = direction
            end
        else
            if isNavigating then
                isNavigating = false
                waypointCoords = nil
                currentDirection = -1
                lastDirection = -1
                arrowPositions = {}
            end
        end
    end
end)

--- Main render thread (every frame for smooth rendering)
CreateThread(function()
    -- Wait for system to be ready
    while not systemReady do
        Wait(100)
    end
    
    while true do
        Wait(Config.UpdateInterval)
        
        if systemReady and isNavigating and not isFrozen then
            local playerPed = PlayerPedId()
            
            if DoesEntityExist(playerPed) then
                local playerPos = GetEntityCoords(playerPed)
                local playerHeading = GetEntityHeading(playerPed)
                
                -- Use vehicle heading if in vehicle
                local vehicle = GetVehiclePedIsIn(playerPed, false)
                if vehicle and DoesEntityExist(vehicle) then
                    playerHeading = GetEntityHeading(vehicle)
                end
                
                CalculateArrowPositions(playerPos, playerHeading, currentDirection, distanceToTurn)
                DrawArrows()
            end
        end
    end
end)

-- ============================================================================
-- DEBUG (Uncomment to enable)
-- ============================================================================

-- Debug thread - ENABLED for testing
CreateThread(function()
    while true do
        Wait(0)
        
        -- Debug: Show system status
        local statusText = "NavArrows | Ready: " .. tostring(systemReady)
        if dui then
            statusText = statusText .. " | DUI: OK"
        else
            statusText = statusText .. " | DUI: nil"
        end
        statusText = statusText .. " | Nav: " .. tostring(isNavigating) .. " | Arrows: " .. #arrowPositions .. " | CurDir: " .. tostring(currentDirection)
        
        if isNavigating and systemReady then
            local dirText = "Unknown(" .. tostring(currentDirection) .. ")"
            
            if currentDirection == DIR_STRAIGHT then dirText = "Straight(5)"
            elseif currentDirection == DIR_LEFT then dirText = "Left(3)"
            elseif currentDirection == DIR_RIGHT then dirText = "Right(4)"
            elseif currentDirection == DIR_SHARP_LEFT then dirText = "SharpL(6)"
            elseif currentDirection == DIR_SHARP_RIGHT then dirText = "SharpR(7)"
            elseif currentDirection == 0 then dirText = "Calc(0)"
            elseif currentDirection == 1 then dirText = "Wrong(1)"
            elseif currentDirection == 8 then dirText = "Recalc(8)"
            end
            
            statusText = statusText .. " | Dir: " .. dirText
        end
        
        SetTextFont(4)
        SetTextProportional(false)
        SetTextScale(0.35, 0.35)
        SetTextColour(255, 255, 255, 255)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(1, 0, 0, 0, 255)
        SetTextDropShadow()
        SetTextOutline()
        SetTextCentre(true)
        BeginTextCommandDisplayText("STRING")
        AddTextComponentSubstringPlayerName(statusText)
        EndTextCommandDisplayText(0.5, 0.05)
    end
end)

-- ============================================================================
-- INITIALIZATION AND CLEANUP
-- ============================================================================

CreateThread(function()
    -- Wait for ox_lib
    while not lib do
        Wait(100)
    end
    
    -- Wait for game session
    while not NetworkIsSessionStarted() do
        Wait(100)
    end
    
    Wait(1000)
    
    print("^2[NavArrows] Initializing Forza-style navigation system...^0")
    
    if InitializeDUI() then
        print("^2[NavArrows] System ready! Set a waypoint to see navigation arrows^0")
    else
        print("^1[NavArrows] Failed to initialize system^0")
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CleanupDUI()
    end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('SetEnabled', function(enabled)
    if enabled then
        isNavigating = waypointCoords ~= nil
    else
        isNavigating = false
        arrowPositions = {}
    end
end)

exports('IsNavigating', function()
    return isNavigating
end)

exports('GetCurrentDirection', function()
    return currentDirection
end)

-- ============================================================================
-- TEST COMMANDS
-- ============================================================================

-- Test command: /testarrow - draws a test arrow on screen to verify DUI works
RegisterCommand('testarrow', function()
    if not dui then
        print("^1[NavArrows] DUI not initialized!^0")
        return
    end
    
    print("^2[NavArrows] Testing DUI sprite...^0")
    print("^2[NavArrows] Dict: " .. tostring(dui.dictName) .. ", Txt: " .. tostring(dui.txtName) .. "^0")
    
    -- Draw test sprite for 5 seconds
    CreateThread(function()
        local endTime = GetGameTimer() + 5000
        while GetGameTimer() < endTime do
            Wait(0)
            DrawSprite(
                dui.dictName,
                dui.txtName,
                0.5, 0.5,       -- Center of screen
                0.15, 0.15,     -- Larger size for testing
                0.0,            -- No rotation
                255, 255, 255, 255
            )
        end
        print("^2[NavArrows] Test complete^0")
    end)
end, false)

-- Test command: /testnav - force enable navigation with direction 5 (straight)
RegisterCommand('testnav', function()
    print("^2[NavArrows] Forcing navigation test mode...^0")
    isNavigating = true
    currentDirection = DIR_STRAIGHT
    systemReady = true
end, false)
