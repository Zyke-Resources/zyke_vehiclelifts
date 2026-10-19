-- The admin command's client half, see server/admin.lua: a see-through copy of the lift stands where the
-- camera meets the floor, and the left mouse button places it there for everyone. Lined up, the copy
-- keeps to the line across or along the nearest lift, turned its way and moved along it in steps, so a
-- row of lifts stands square. Free, it goes anywhere and the scroll wheel turns it a degree at a time,
-- ten with Shift held. Each lift placed is saved by the server, see server/database.lua, and the
-- tool stays out for the next one until the right mouse button puts it away. Z switches it to taking
-- lifts away: the lift aimed at is marked on the floor and the left mouse button takes it away, if it
-- was placed with the tool. Nothing here runs while the tool is put away

-- Metres from the player the copy may stand, which the server allows a little over
local placeReach = 12.0
-- Metres from the cursor a lift is lined up with, how much nearer another line has to be to take over,
-- and the step the copy moves along a line in
local lineRange = 30.0
local lineKeep = 0.3
local lineStep = 0.05
-- Metres a line is drawn out from the lift it runs through, and off the floor so it does not flicker in it
local lineLength = 30.0
local lineLift = 0.03
-- Degrees a turn of the scroll wheel turns the copy, and with Shift held
local turnStep = 1.0
local turnFast = 10.0
local shiftControl = 21
-- Switch between lined up and free, and between placing and taking away. G is zyke_vehiclekeys' menu,
-- X is hands up on many servers and R is zyke_anglegrinder's menu
local lineKey = "C"
local removeKey = "Z"
-- Metres above or below a lift's floor the cursor may be to aim at it, and what the line of sight meets
-- while placing, the map, and while taking lifts away, the map and the lifts' solid props
local floorSlack = 1.0
local placeFlags = 1
local removeFlags = 17
local ghostAlpha = 170
local modelTimeout = 5000
-- Attack, aim, melee, the weapon wheel, sprint, which Shift is, and the pause menu
local blockedControls = {24, 25, 140, 141, 142, 257, 263, 264, 14, 15, 16, 17, 37, 21, 199, 200}
local colours = {line = {255, 255, 255, 150}, arrow = {110, 200, 130, 220}, wrong = {225, 60, 60, 220}}
-- The box round the lift aimed at while taking lifts away, as zyke_chopshop marks what it picks up, and
-- red for one the tool can not take away
---@type {removable: LiftBoxColours, kept: LiftBoxColours}
local boxColours = {
    removable = {floor = {110, 170, 255, 110}, side = {150, 185, 255, 38}, edge = {200, 220, 255, 140}},
    kept = {floor = {225, 60, 60, 110}, side = {225, 60, 60, 38}, edge = {255, 140, 140, 140}},
}

-- Metres the box stands over the tallest prop
local boxClearance = 0.05
---@type table<LiftKindName, number> @ How tall each kind's props stand, read from their models once
local boxHeights = {}

---@class LiftPlaceLine
---@field liftId integer
---@field axis "across" | "along"

---@class LiftPlaceSession
---@field kind LiftKindName
---@field removing boolean @ Takes lifts away instead of placing them
---@field hover? integer @ The lift aimed at while taking lifts away
---@field heading number @ Degrees, the way it is turned while free
---@field lined boolean @ Keeps to the line of the nearest lift
---@field line? LiftPlaceLine @ The line it keeps to now
---@field onLine boolean @ The keys were set for it keeping to a line
---@field coords? vector3 @ Where it stands now, nil while the camera is not on the floor
---@field placeHeading number @ The way it is turned now, the line's lift's while lined up
---@field along? number @ Metres along the line from the lift it runs through
---@field warning? string @ Locale key of why it can not be placed or taken away here
---@field ghosts table<string, integer> @ The copy's props, by piece
---@field keybinds LiftKeybindItem[]
---@field shown? string @ What the panel shows, so it is only sent when it changes
---@field busy boolean @ The server is being asked
---@field done boolean

---@type LiftPlaceSession?
local placing

---@return boolean placing @ True while the admin has the placing tool out
function IsPlacingLift()
    return placing ~= nil
end

---@param from vector3
---@param to vector3
---@param flags? integer @ What the line meets, the map by default
---@return vector3? hit @ Where the line first meets it
---@return integer entity @ The entity it met, 0 for the map
local function probe(from, to, flags)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags or placeFlags, PlayerPedId(), 0)
    local _, hit, at, _, entity = GetShapeTestResult(handle)

    return hit == 1 and at or nil, entity
end

---@param flags integer
---@return vector3? cursor @ Where the middle of the screen meets the floor, or a prop with removeFlags
---@return integer entity
local function getCursor(flags)
    local from = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local direction = vec3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local reach = #(from - GetEntityCoords(PlayerPedId())) + placeReach + 5.0

    return probe(from, from + direction * reach, flags)
end

---@param heading number
---@return vector2 across @ The lift's X in the world
---@return vector2 along @ Its Y, the way a car's nose points when it is driven in
local function getAxes(heading)
    local turn = math.rad(heading)
    local c, s = math.cos(turn), math.sin(turn)

    return vec2(c, s), vec2(-s, c)
end

---@param lift ZykeVehicleLift
---@param axis "across" | "along"
---@return vector2 direction
local function getLineDirection(lift, axis)
    local across, along = getAxes(lift.heading)

    return axis == "across" and across or along
end

---@param lift ZykeVehicleLift
---@param axis "across" | "along"
---@param cursor vector3
---@return number off @ Metres from the cursor to the line
---@return number along @ Metres along the line from the lift to the cursor
local function measureLine(lift, axis, cursor)
    local direction = getLineDirection(lift, axis)
    local offset = cursor.xy - lift.coords.xy
    local along = offset.x * direction.x + offset.y * direction.y

    return #(offset - direction * along), along
end

-- The line nearest the cursor, across or along a lift in the player's routing bucket. The line held
-- now stays until another one is clearly nearer, so the copy does not flicker between two
---@param session LiftPlaceSession
---@param cursor vector3
---@return LiftPlaceLine? line
local function findLine(session, cursor)
    local bucket = LocalPlayer.state.routingBucket or 0
    local held = session.line
    local best, bestOff, keptOff

    for liftId, lift in pairs(GetLifts()) do
        if ((lift.bucket == nil or lift.bucket == bucket) and #(lift.coords.xy - cursor.xy) <= lineRange) then
            for _, axis in ipairs({"across", "along"}) do
                local off = measureLine(lift, axis, cursor)

                if (held and held.liftId == liftId and held.axis == axis) then keptOff = off end
                if (not bestOff or off < bestOff) then best, bestOff = {liftId = liftId, axis = axis}, off end
            end
        end
    end

    if (keptOff and keptOff <= bestOff + lineKeep) then return held end

    return best
end

-- Where the copy stands for the cursor: on it while free, and on the nearest line while lined up, on
-- the floor under that spot
---@param session LiftPlaceSession
---@param cursor vector3
local function locate(session, cursor)
    session.line = session.lined and findLine(session, cursor) or nil

    local line = session.line
    local lift = line and GetLift(line.liftId)

    if (not line or not lift) then
        session.coords = cursor
        session.placeHeading = session.heading
        session.along = nil

        return
    end

    local _, along = measureLine(lift, line.axis, cursor)
    along = math.floor(along / lineStep + 0.5) * lineStep

    local at = lift.coords.xy + getLineDirection(lift, line.axis) * along
    local floor = probe(vec3(at.x, at.y, cursor.z + 1.0), vec3(at.x, at.y, cursor.z - 2.0))

    session.coords = vec3(at.x, at.y, floor and floor.z or cursor.z)
    session.placeHeading = lift.heading
    session.along = along
end

-- The lift whose floor the cursor is on, the one whose middle is nearest where two overlap
---@param cursor vector3
---@return integer? liftId
local function findHovered(cursor)
    local bucket = LocalPlayer.state.routingBucket or 0
    local best, bestDistance

    for liftId, lift in pairs(GetLifts()) do
        local footprint = LiftKinds[lift.kind].footprint
        local point = GetLiftPoint(lift, cursor)
        local distance = #point.xy
        local under = math.abs(point.x) <= footprint.x and math.abs(point.y) <= footprint.y and math.abs(point.z) <= floorSlack

        if ((lift.bucket == nil or lift.bucket == bucket) and under and (not bestDistance or distance < bestDistance)) then best, bestDistance = liftId, distance end
    end

    return best
end

-- Only a lift placed with the tool is taken away with it, since one of shared/lifts.lua or of another
-- resource is made again as that starts
---@param session LiftPlaceSession
---@return string? warning
local function getRemoveWarning(session)
    local lift = session.hover and GetLift(session.hover)
    if (not lift) then return "place:noLift" end
    if (not lift.placed) then return "place:notPlaced" end
    if (#(lift.coords - GetEntityCoords(PlayerPedId())) > placeReach) then return "place:tooFar" end

    return nil
end

---@param session LiftPlaceSession
---@return boolean overlapping @ The copy stands in a lift that stands already
local function isOverlapping(session)
    local placed = {kind = session.kind, coords = session.coords, heading = session.placeHeading}

    for _, lift in pairs(GetLifts()) do
        if (DoLiftsOverlap(lift, placed)) then return true end
    end

    return false
end

---@param session LiftPlaceSession
local function updateWarning(session)
    local coords = session.coords

    if (session.removing) then
        session.warning = getRemoveWarning(session)
    elseif (not coords) then
        session.warning = "place:noFloor"
    elseif (#(coords - GetEntityCoords(PlayerPedId())) > placeReach) then
        session.warning = "place:tooFar"
    elseif (isOverlapping(session)) then
        session.warning = "place:overlap"
    else
        session.warning = nil
    end
end

---@param value number
---@return string shown @ To a tenth, without a trailing .0
local function formatNumber(value)
    return ("%g"):format(math.floor(value * 10.0 + 0.5) / 10.0)
end

-- The keys, with the way the copy is turned and what it keeps to beside the title, sent only when that changed
---@param session LiftPlaceSession
local function showPanel(session)
    local title, detail

    if (session.removing) then
        title = T("title:removeLift")
        detail = session.hover and T("place:liftId", {session.hover}) or nil
    else
        local heading = T("place:heading", {formatNumber(session.placeHeading % 360.0)})
        local line = session.line

        title = T("title:placeLift")
        detail = line and ("%s  ·  %s"):format(heading, T("place:linedUp", {line.liftId, ("%.2f"):format(math.abs(session.along or 0.0))})) or heading
    end

    local warning = session.warning and T(session.warning) or nil
    local shown = ("%s|%s|%s"):format(title, detail or "", warning or "")
    if (shown == session.shown) then return end

    session.shown = shown

    LiftKeybinds.show(session.keybinds, {title = title, detail = detail, warning = warning})
end

-- The server places it, while the frames go on
---@param session LiftPlaceSession
local function confirm(session)
    if (session.busy) then return end

    local coords, heading, kind = session.coords, session.placeHeading % 360.0, session.kind
    if (session.warning or not coords) then Z.notify("actionUnavailable") return end

    session.busy = true

    CreateThread(function()
        local liftId, notification = Z.callback.await("zyke_vehiclelifts:AddLift", coords, heading, kind)

        session.busy = false

        if (not liftId) then Z.notify(notification or "actionUnavailable") return end

        Z.notify("adminLiftPlaced", {liftId})
    end)
end

-- The server takes the lift aimed at away, while the frames go on
---@param session LiftPlaceSession
local function removeHovered(session)
    if (session.busy) then return end

    local liftId = session.hover
    if (session.warning or not liftId) then Z.notify("actionUnavailable") return end

    session.busy = true

    CreateThread(function()
        local removed, notification = Z.callback.await("zyke_vehiclelifts:RemovePlacedLift", liftId)

        session.busy = false

        if (not removed) then Z.notify(notification or "actionUnavailable") return end

        Z.notify("liftRemoved", {liftId})
    end)
end

---@param session LiftPlaceSession
---@param key string
local function turn(session, key)
    local step = IsDisabledControlPressed(0, shiftControl) and turnFast or turnStep

    session.heading = (session.heading + (key == "SCROLLUP" and step or -step)) % 360.0
end

---@param session LiftPlaceSession
local function setKeys(session)
    local keybinds

    session.onLine = session.line ~= nil

    if (session.removing) then
        keybinds = {{label = T("control:removeLift"), key = "LEFTMOUSE", func = function() removeHovered(session) end}}
    else
        keybinds = {{label = T("control:placeLift"), key = "LEFTMOUSE", func = function() confirm(session) end}}

        -- On a line, the lift it lines up with turns it. With none near it stands free
        if (not session.onLine) then
            keybinds[#keybinds + 1] = {label = T("control:placeTurn"), key = {"SCROLLUP", "SCROLLDOWN"}, func = function(key) turn(session, key) end}
            keybinds[#keybinds + 1] = {label = T("control:placeTurnFast"), key = "LEFTSHIFT", func = function() end}
        end

        keybinds[#keybinds + 1] = {
            label = T(session.lined and "control:placeFree" or "control:placeLine"),
            key = lineKey,
            func = function()
                session.lined = not session.lined
                -- Free again, it stays turned the way the line had it
                session.heading = session.placeHeading

                setKeys(session)
            end,
        }
    end

    keybinds[#keybinds + 1] = {
        label = T(session.removing and "control:modePlace" or "control:modeRemove"),
        key = removeKey,
        func = function()
            session.removing = not session.removing
            session.hover = nil

            setKeys(session)
        end,
    }
    keybinds[#keybinds + 1] = {label = T("control:placeDone"), key = "RIGHTMOUSE", hiddenKey = {"ESC", "BACKSPACE"}, func = function() session.done = true end}

    session.keybinds = keybinds
    session.shown = nil
end

---@param session LiftPlaceSession
local function clearGhosts(session)
    for _, entity in pairs(session.ghosts) do
        DeleteEntity(entity)
    end

    session.ghosts = {}
end

---@param session LiftPlaceSession
---@return boolean made @ False when a model could not be loaded
local function makeGhosts(session)
    local set = LiftSets[session.kind]
    local at = GetEntityCoords(PlayerPedId()) - vec3(0.0, 0.0, 50.0)

    for _, name in pairs(set.models) do
        if (not Z.loadModel(name, true, modelTimeout)) then return false end
    end

    for _, piece in ipairs(set.pieces(0.0, {}, nil, false)) do
        local entity = CreateObjectNoOffset(joaat(piece.model), at.x, at.y, at.z, false, false, false)

        SetEntityCollision(entity, false, false)
        FreezeEntityPosition(entity, true)
        SetEntityAlpha(entity, ghostAlpha, false)

        session.ghosts[piece.key] = entity
    end

    return true
end

---@param session LiftPlaceSession
local function poseGhosts(session)
    local coords = session.coords

    for _, entity in pairs(session.ghosts) do
        SetEntityVisible(entity, coords ~= nil, false)
    end

    if (not coords) then return end

    local frame = {coords = coords, heading = session.placeHeading}

    for _, piece in ipairs(LiftSets[session.kind].pieces(0.0, {}, nil, false)) do
        local entity = session.ghosts[piece.key]

        -- A copy of another kind may still be loading
        if (entity) then
            local at = GetLiftWorld(frame, piece.at)

            SetEntityCoordsNoOffset(entity, at.x, at.y, at.z, false, false, false)
            SetEntityRotation(entity, piece.pitch or 0.0, piece.roll or 0.0, frame.heading + piece.yaw, 2, false)
        end
    end
end

-- The line it keeps to, and an arrow the way a car is driven in, red where it can not be placed
---@param session LiftPlaceSession
local function drawGuides(session)
    local coords = session.coords
    if (not coords) then return end

    local line = session.line
    local lift = line and GetLift(line.liftId)
    local z = coords.z + lineLift

    if (lift) then
        local direction = getLineDirection(lift, line.axis) * lineLength
        local middle = vec3(lift.coords.x, lift.coords.y, z)

        LiftDraw.line(middle - vec3(direction.x, direction.y, 0.0), middle + vec3(direction.x, direction.y, 0.0), colours.line)
    end

    local across, along = getAxes(session.placeHeading)
    local tip = coords.xy + along * 2.5
    local colour = session.warning and colours.wrong or colours.arrow
    local base = vec3(coords.x, coords.y, z)
    local head = vec3(tip.x, tip.y, z)

    LiftDraw.line(base, head, colour)
    LiftDraw.line(head, vec3(tip.x - along.x * 0.4 + across.x * 0.3, tip.y - along.y * 0.4 + across.y * 0.3, z), colour)
    LiftDraw.line(head, vec3(tip.x - along.x * 0.4 - across.x * 0.3, tip.y - along.y * 0.4 - across.y * 0.3, z), colour)
end

-- The props stand on a lift this client shows, so their models are loaded by the time one is aimed at
---@param kindName LiftKindName
---@return number height @ Metres, the top of the tallest prop with the carriages down
local function getBoxHeight(kindName)
    if (boxHeights[kindName]) then return boxHeights[kindName] end

    local top = 0.0

    for _, piece in ipairs(LiftSets[kindName].pieces(0.0, {}, nil, false)) do
        local _, most = GetModelDimensions(joaat(piece.model))

        top = math.max(top, piece.at.z + most.z)
    end

    -- A model not loaded yet reads as nothing, and is read again the next frame
    if (top > 0.0) then boxHeights[kindName] = top + boxClearance end

    return top + boxClearance
end

-- The box round the lift aimed at while taking lifts away
---@param session LiftPlaceSession
local function drawHover(session)
    local lift = session.hover and GetLift(session.hover)
    if (not lift) then return end

    LiftDraw.box(lift, LiftKinds[lift.kind].footprint, getBoxHeight(lift.kind), session.warning and boxColours.kept or boxColours.removable)
end

---@param session LiftPlaceSession
local function runFrame(session)
    local cursor, entity = getCursor(session.removing and removeFlags or placeFlags)

    if (session.removing) then
        session.coords = nil
        session.line = nil
        -- A post or the power unit aimed at is its lift's, and a floor between them the nearest lift's
        session.hover = GetLiftOfEntity(entity) or (cursor and findHovered(cursor)) or nil
    elseif (cursor) then
        locate(session, cursor)
    else
        session.coords = nil
        session.line = nil
    end

    if ((session.line ~= nil) ~= session.onLine) then setKeys(session) end

    updateWarning(session)
    poseGhosts(session)
    drawGuides(session)
    drawHover(session)
    showPanel(session)

    for i = 1, #blockedControls do
        DisableControlAction(0, blockedControls[i], true)
    end

    DisablePlayerFiring(PlayerId(), true)
    LiftKeybinds.handle(session.keybinds)
end

-- Takes the tool out until the admin puts it away. With it out already, it changes to the new kind
---@param kind LiftKindName
RegisterNetEvent("zyke_vehiclelifts:PlaceLift", function(kind)
    if (not LiftSets[kind]) then return end

    if (placing) then
        clearGhosts(placing)

        placing.kind = kind

        if (not makeGhosts(placing)) then placing.done = true end

        return
    end

    local ped = PlayerPedId()
    if (IsWorkingLift() or IsPlayerBusy() or IsPedInAnyVehicle(ped, false)) then Z.notify("actionUnavailable") return end

    local heading = math.floor(GetGameplayCamRot(2).z + 0.5) % 360.0

    ---@type LiftPlaceSession
    local session = {kind = kind, removing = false, heading = heading, placeHeading = heading, lined = true, onLine = false, ghosts = {}, keybinds = {}, busy = false, done = false}
    placing = session

    setKeys(session)

    if (makeGhosts(session)) then
        while (not session.done and placing == session and not IsEntityDead(ped)) do
            runFrame(session)

            Wait(0)
        end
    end

    LiftKeybinds.hide(session.keybinds)
    clearGhosts(session)

    for _, name in pairs(LiftSets[session.kind].models) do
        -- The lifts standing near the player keep the models they use loaded themselves
        SetModelAsNoLongerNeeded(joaat(name))
    end

    if (placing == session) then placing = nil end
end)

-- A restart while the tool is out would leave the copy standing
---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName or not placing) then return end

    clearGhosts(placing)
    LiftKeybinds.hide(placing.keybinds)
end)