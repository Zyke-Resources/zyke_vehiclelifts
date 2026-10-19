-- Stands every lift near the player as this client's own props, from the zykeVehicleLifts global state, and
-- lets the player work one at its power unit. The carriages travel by the server's game timer, so
-- every client draws them at the same height without being told each frame, and the car on the pads
-- is posed from its own record the same way, see client/cars.lua. At the power unit holding E
-- holds the button that sends the carriages up and holding Q the handle that lets them down; the
-- server stops them at each height by itself, see server/lifts.lua. W and S send them all the
-- way up or down with no key held, and Space stops them. Nothing here runs while no lift stands, a
-- lift at rest is not touched, and only one that travels near the player is drawn every frame
local streamIn = 90.0
local streamOut = 110.0
local checkMs = 1000
local modelTimeout = 5000
-- Metres from the power unit the lift is offered, and from where the player stands at it they may
-- wander before they let go of it
local powerReach = 2.0
local leverSlack = 1.2
-- Metres from a lift its interaction points are looked at
local pointRange = 8.0
-- How long the player gets to walk to the power unit
local walkTimeout = 2500
-- Milliseconds the carriages a player sent off have to set off in, before the key that stops them goes
local sendSettleMs = 1500
-- Milliseconds between two reads of the vehicles a travelling lift's sounds pass through
local ignoreMs = 1000
local workAnim = {dict = "amb@prop_human_atm@male@idle_a", clip = "idle_a"}
-- Looking round stays free at the power unit, so the player can watch the car go up
local lookControls = {1, 2, 249}
-- E and Q, held to raise and lower the carriages
local raiseControl = 38
local lowerControl = 44

---@type table<integer, ZykeVehicleLift>
local lifts = {}
---@type table<integer, ShownLift> @ The lifts this client stands props for, by lift
local shown = {}
---@type table<integer, LiftArm[]> @ Arms the arm bench on this client is moving, drawn in place of the lift's own
local held = {}
local streaming = false
local working = false

---@param liftId integer
---@return ZykeVehicleLift? lift
function GetLift(liftId)
    return lifts[liftId]
end

---@return table<integer, ZykeVehicleLift> lifts @ Every lift in the zykeVehicleLifts global state, by id
function GetLifts()
    return lifts
end

---@param liftId integer
---@return integer? plate @ The floor plate this client stands for the lift, nil while it stands none
function GetLiftPlate(liftId)
    local entry = shown[liftId]

    return entry and entry.entities.plate or nil
end

---@param lift ZykeVehicleLift
---@return number travel @ Metres the carriages stand up on this client now
---@return boolean moving
function GetLiftTravelNow(lift)
    return GetLiftTravel(lift, ServerClock.timer())
end

-- The car the arms were set under, read by its net id, while it is up on the pads
---@param lift ZykeVehicleLift
---@return LiftPads? pads
local function getPads(lift)
    local car = lift.netId and GetStateBagValue(("entity:%d"):format(lift.netId), "zykeVehicleLift")
    if (not car or car.liftId ~= lift.id) then return nil end

    return LiftSets[lift.kind].pads(lift, car, ServerClock.timer())
end

-- Puts every prop of a lift where its state has it now
---@param liftId integer
---@return boolean moving @ The carriages travel, or the car on the pads eases to a trim
local function draw(liftId)
    local entry, lift = shown[liftId], lifts[liftId]
    if (not entry or not lift) then return false end

    local travel, moving = GetLiftTravelNow(lift)
    local lowering = moving and lift.goal < lift.travel
    local pads = getPads(lift)

    for _, piece in ipairs(LiftSets[lift.kind].pieces(travel, held[liftId] or lift.arms, pads, lowering)) do
        local entity = entry.entities[piece.key]

        if (entity) then
            local at = GetLiftWorld(lift, piece.at)

            SetEntityCoordsNoOffset(entity, at.x, at.y, at.z, false, false, false)
            SetEntityRotation(entity, piece.pitch or 0.0, piece.roll or 0.0, lift.heading + piece.yaw, 2, false)
        end
    end

    entry.travel = travel

    return moving or (pads ~= nil and pads.moving)
end

-- Draws a travelling lift every frame until it stops. Its sounds are played by the server, see
-- server/sounds.lua, and the vehicles around it are read now and then so they do not muffle them
---@param liftId integer
local function follow(liftId)
    local entry = shown[liftId]
    if (not entry or entry.following) then return end

    entry.following = true

    CreateThread(function()
        local ignoredAt = 0

        while (shown[liftId] == entry and draw(liftId)) do
            local now = GetGameTimer()

            if (now - ignoredAt >= ignoreMs) then
                ignoredAt = now

                SetLiftSoundIgnores(liftId, lifts[liftId].coords, entry.entities)
            end

            Wait(0)
        end

        entry.following = false
    end)
end

---@param set LiftSet
---@return string[] names
local function getModelNames(set)
    local names = {}

    for _, name in pairs(set.models) do
        names[#names + 1] = name
    end

    return names
end

---@param liftId integer
---@return boolean stood @ False when a model could not be loaded
local function spawn(liftId)
    local lift = lifts[liftId]
    local set = LiftSets[lift.kind]
    if (not set) then return false end

    for _, name in ipairs(getModelNames(set)) do
        if (not Z.loadModel(name, true, modelTimeout)) then return false end
    end

    -- The lift may have gone while its models loaded
    if (shown[liftId] or lifts[liftId] ~= lift) then return false end

    local entities = {}

    for _, piece in ipairs(set.pieces(0.0, lift.arms, nil, false)) do
        local at = GetLiftWorld(lift, piece.at)
        local entity = CreateObjectNoOffset(joaat(piece.model), at.x, at.y, at.z, false, false, false)

        FreezeEntityPosition(entity, true)
        SetEntityLodDist(entity, math.floor(streamOut))

        if (not set.solid[piece.key:match("^%a+")]) then SetEntityCollision(entity, false, false) end

        entities[piece.key] = entity
    end

    shown[liftId] = {entities = entities, following = false}

    if (draw(liftId)) then follow(liftId) end

    return true
end

---@param liftId integer
local function despawn(liftId)
    local entry = shown[liftId]
    if (not entry) then return end

    shown[liftId] = nil

    ClearLiftSoundIgnores(liftId)

    for _, entity in pairs(entry.entities) do DeleteEntity(entity) end
end

-- Stands the lifts within reach of the player and takes away those left behind, once a second and
-- only while a lift stands. A lift in another routing bucket is never stood
local function stream()
    if (streaming) then return end

    streaming = true

    RunLiftInteractionPoints(function()
        return streaming
    end)

    CreateThread(function()
        while (next(lifts)) do
            local coords = GetEntityCoords(PlayerPedId())
            -- zyke_lib keeps the player's bucket in their state
            local bucket = LocalPlayer.state.routingBucket or 0

            for liftId, lift in pairs(lifts) do
                local here = lift.bucket == nil or lift.bucket == bucket
                local distance = #(coords - lift.coords)

                if (here and distance <= streamIn and not shown[liftId]) then
                    spawn(liftId)
                elseif ((not here or distance > streamOut) and shown[liftId]) then
                    despawn(liftId)
                end
            end

            Wait(checkMs)
        end

        for liftId in pairs(shown) do despawn(liftId) end

        for _, set in pairs(LiftSets) do
            for _, name in ipairs(getModelNames(set)) do SetModelAsNoLongerNeeded(joaat(name)) end
        end

        streaming = false
    end)
end

-- A lift that was taken away and one made again in its place are different lifts, and their props
-- are stood again
---@param value? table<integer, ZykeVehicleLift>
local function setLifts(value)
    local before = lifts

    lifts = value or {}

    for liftId in pairs(shown) do
        local lift, old = lifts[liftId], before[liftId]
        if (not lift or not old or lift.kind ~= old.kind or lift.coords ~= old.coords or lift.heading ~= old.heading) then despawn(liftId) end
    end

    for liftId in pairs(shown) do
        if (draw(liftId)) then follow(liftId) end
    end

    if (next(lifts)) then stream() end
end

-- The car on a lift's pads changed its record, which the pads follow
---@param liftId integer
function RedrawLift(liftId)
    if (draw(liftId)) then follow(liftId) end
end

-- The arm bench on this client draws the arms it moves before the server has them
---@param liftId integer
---@param arms? LiftArm[] @ Nil to draw the lift's own again
function SetLiftArmsHeld(liftId, arms)
    held[liftId] = arms

    draw(liftId)
end

-- The lift a vehicle stands between the posts of, as it stands on its wheels with the carriages down.
-- Where lifts stand in each other it is the one whose middle is nearest, so it does not change with the
-- order the lifts were made in
---@param vehicle integer
---@return integer? liftId
function FindLiftUnder(vehicle)
    local coords = GetEntityCoords(vehicle)
    local best, bestDistance

    for liftId, lift in pairs(lifts) do
        local point = GetLiftPoint(lift, coords)
        local distance = #point.xy

        if (shown[liftId] and LiftSets[lift.kind].isBetween(point) and (not bestDistance or distance < bestDistance)) then best, bestDistance = liftId, distance end
    end

    return best
end

---@param coords vector3
---@return integer[] liftIds @ The lifts this client stands props for that are near enough to mark their interaction points
function GetShownLiftsNear(coords)
    local liftIds = {}

    for liftId in pairs(shown) do
        local lift = lifts[liftId]
        if (lift and #(coords - lift.coords) <= pointRange) then liftIds[#liftIds + 1] = liftId end
    end

    return liftIds
end

---@param entity integer
---@return integer? liftId @ The lift one of whose props this client stands the entity is
function GetLiftOfEntity(entity)
    if (entity == 0) then return nil end

    for liftId, entry in pairs(shown) do
        for _, prop in pairs(entry.entities) do
            if (prop == entity) then return liftId end
        end
    end

    return nil
end

---@param entity integer
---@return integer? liftId @ The lift whose power unit the entity is
local function findPower(entity)
    for liftId, entry in pairs(shown) do
        if (entry.entities.power == entity) then return liftId end
    end

    return nil
end

---@param lift ZykeVehicleLift
---@return vector3 at @ World, where the player stands at the power unit
---@return number heading @ Facing it, back across the lift
local function getOperatorSpot(lift)
    local operator = LiftKinds[lift.kind].operatorAt

    return GetLiftWorld(lift, vec3(operator.x, operator.y, 0.0)), (lift.heading + 90.0) % 360.0
end

---@param dir 1 | -1 | 0
---@return LiftAction? action @ What the gate is asked about, nil for letting go or stopping
local function getAction(dir)
    if (dir == 0) then return nil end

    return dir > 0 and "up" or "down"
end

---@param power LiftPowerSession
---@param dir 1 | -1 | 0
---@return boolean allowed @ The gate lets the player move the carriages that way, and was told why not
local function canMove(power, dir)
    local action = getAction(dir)
    if (not action) then return true end

    local allowed, reason = CanWorkLift(power.liftId, action)
    if (not allowed) then Z.notify(reason or "actionUnavailable") end

    return allowed
end

-- A key held or let go of. Holding one takes the carriages over from a send
---@param power LiftPowerSession
---@param button 1 | -1 | 0
local function pressButton(power, button)
    power.pressed = button

    if (not canMove(power, button)) then return end

    TriggerServerEvent("zyke_vehiclelifts:LiftLever", power.sessionId, button)

    if (button ~= 0) then power.sending = 0 end
end

-- Sends the carriages all the way up or down with no button held, or stops them on the lock below
---@param power LiftPowerSession
---@param dir 1 | -1 | 0
local function sendLift(power, dir)
    if (not canMove(power, dir)) then return end

    TriggerServerEvent("zyke_vehiclelifts:SendLift", power.sessionId, dir)

    power.sending = dir
    power.sentAt = GetGameTimer()
end

-- Carriages this player sent off that got where they were going, or never set off, need no stopping
---@param power LiftPowerSession
---@param lift ZykeVehicleLift
local function updateSending(power, lift)
    if (power.sending == 0 or GetGameTimer() < power.sentAt + sendSettleMs) then return end

    local _, moving = GetLiftTravelNow(lift)
    if (not moving) then power.sending = 0 end
end

-- The power unit's keys, with the one that stops the carriages only while this player has them going
-- by themselves
---@param power LiftPowerSession
local function setPowerKeys(power)
    local items = {
        -- The loop reads the held keys itself to follow the hold
        {label = T("control:liftUp"), key = "E", func = function() end},
        {label = T("control:liftDown"), key = "Q", func = function() end},
        {label = T("control:liftTop"), key = "W", func = function() sendLift(power, 1) end},
        {label = T("control:liftBottom"), key = "S", func = function() sendLift(power, -1) end},
    }

    if (power.sending ~= 0) then items[#items + 1] = {label = T("control:halt"), key = "SPACE", func = function() sendLift(power, 0) end} end

    items[#items + 1] = {label = T("control:leave"), key = "ESC", hiddenKey = "BACKSPACE", func = function() power.done = true end}
    power.keybinds = items
    power.halting = power.sending ~= 0

    LiftKeybinds.show(items, {title = T("title:workLift")})
end

-- The player at the power unit until they leave it: a key for as long as it is held, and one that
-- sends the carriages all the way and leaves them going
---@param liftId integer
local function workLift(liftId)
    local lift = lifts[liftId]
    if (not lift or IsWorkingLift() or IsPlayerBusy()) then return end

    local sessionId, notification = Z.callback.await("zyke_vehiclelifts:WorkLift", liftId)
    if (not sessionId) then Z.notify(notification or "actionUnavailable") return end

    working = true

    local ped = PlayerPedId()
    local at, heading = getOperatorSpot(lift)
    local arriveBy = GetGameTimer() + walkTimeout

    TaskGoStraightToCoord(ped, at.x, at.y, at.z, 1.0, walkTimeout, heading, 0.1)

    while (GetGameTimer() < arriveBy and #(GetEntityCoords(ped).xy - at.xy) > 0.25) do Wait(50) end

    SetEntityHeading(ped, heading)

    if (Z.loadDict(workAnim.dict, true, 3000)) then TaskPlayAnim(ped, workAnim.dict, workAnim.clip, 4.0, 4.0, -1, 1, 0.0, false, false, false) end

    ---@type LiftPowerSession
    local power = {liftId = liftId, sessionId = sessionId, pressed = 0, heldOver = true, sending = 0, sentAt = 0, done = false}

    setPowerKeys(power)

    while (not power.done) do
        local button = IsDisabledControlPressed(0, raiseControl) and 1 or (IsDisabledControlPressed(0, lowerControl) and -1 or 0)

        -- E also takes the power unit, so a key still down from then only counts once it is let go
        if (button == 0) then power.heldOver = false end
        if (button ~= power.pressed and not power.heldOver) then pressButton(power, button) end

        lift = lifts[liftId]

        if (not lift or IsEntityDead(ped) or IsPedRagdoll(ped) or #(GetEntityCoords(ped).xy - at.xy) > leverSlack) then
            power.done = true
        else
            updateSending(power, lift)
        end

        if ((power.sending ~= 0) ~= power.halting) then setPowerKeys(power) end

        DisableAllControlActions(0)

        for i = 1, #lookControls do EnableControlAction(0, lookControls[i], true) end

        LiftKeybinds.handle(power.keybinds)

        Wait(0)
    end

    LiftKeybinds.hide(power.keybinds)
    TriggerServerEvent("zyke_vehiclelifts:LeaveLift", sessionId)
    StopAnimTask(ped, workAnim.dict, workAnim.clip, 2.0)
    LiftScene.holdPauseMenu()

    working = false
end

---@return boolean working @ True while the player stands at a lift's power unit, sets its arms or places one
function IsWorkingLift()
    return working or IsLiftSceneOpen() or IsPlacingLift()
end

-- The power unit of every lift near the player, see client/interactions.lua
---@param add fun(point: LiftInteractionPoint)
---@param pedCoords vector3
RegisterLiftInteractionPoints(function(add, pedCoords)
    local liftIds = GetShownLiftsNear(pedCoords)
    if (#liftIds == 0 or IsPlayerBusy()) then return end

    for i = 1, #liftIds do
        local liftId = liftIds[i]
        local lift = lifts[liftId]

        add({
            id = "power:" .. liftId,
            coords = GetLiftWorld(lift, LiftKinds[lift.kind].powerAt),
            reach = powerReach,
            label = T("target:workLift"),
            ---@return boolean canInteract
            canInteract = function()
                return shown[liftId] ~= nil and not IsPlayerBusy()
            end,
            onSelect = function()
                workLift(liftId)
            end,
        })
    end
end)

---@param bagName string
---@param key string
---@param value? table<integer, ZykeVehicleLift>
AddStateBagChangeHandler("zykeVehicleLifts", "global", function(bagName, key, value)
    -- Carriages that were just sent off travel from where they stand now, not seconds later
    for _, lift in pairs(value or {}) do
        ServerClock.atLeast(lift.movedAt)
    end

    setLifts(value)
end)

---@param liftId integer
---@return ZykeVehicleLift? lift
exports("GetLift", GetLift)

---@param liftId integer
---@return number? travel @ Metres the carriages stand up on this client now, nil for no such lift
---@return boolean moving
exports("GetLiftTravel", function(liftId)
    local lift = lifts[liftId]
    if (not lift) then return nil, false end

    return GetLiftTravelNow(lift)
end)

exports("IsWorkingLift", IsWorkingLift)

---@param vehicle integer
---@return integer? liftId @ The lift the vehicle stands between the posts of
exports("GetLiftUnder", FindLiftUnder)

CreateThread(function()
    -- The carriages travel by the server's game timer, which is asked for before anyone works a lift
    ServerClock.timer()

    setLifts(GlobalState.zykeVehicleLifts)

    -- zyke_lib picks the target system while it loads
    while (not HasLoaderFinished) do Wait(100) end

    if (UsesLiftInterestPoints()) then return end

    for kindName, set in pairs(LiftSets) do
        Z.target.addModel(set.models.power, {
            distance = powerReach,
            options = {
                {
                    name = "zyke_vehiclelifts:work_" .. kindName,
                    icon = "fas fa-arrows-up-down",
                    label = T("target:workLift"),
                    ---@param entity integer
                    ---@return boolean canInteract
                    canInteract = function(entity)
                        return not IsWorkingLift() and findPower(entity) ~= nil and not IsPlayerBusy()
                    end,
                    ---@param data {entity: integer} | integer @ ox_target passes the option data, qb-target the entity
                    onSelect = function(data)
                        local liftId = findPower(type(data) == "table" and data.entity or data)
                        if (liftId) then workLift(liftId) end
                    end,
                },
            },
        })
    end
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName) then return end

    for liftId in pairs(shown) do despawn(liftId) end

    if (working) then StopAnimTask(PlayerPedId(), workAnim.dict, workAnim.clip, 2.0) end
end)