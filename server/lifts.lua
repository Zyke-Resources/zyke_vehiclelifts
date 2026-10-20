-- Runs every lift: where its carriages stand and where they are going, where each of its arms is set and
-- the car whose jacking points they were set under. The lifts are the zykeVehicleLifts global state,
-- which every client stands its props from, see client/lifts.lua. A lift stands from
-- shared/lifts.lua, from the admin command or from another resource through CreateLift, and
-- belongs to the resource that made it. The player at the power unit holds a button and the carriages
-- travel for everyone at once, a stop at a time. Let go of between two, they come down onto the lock
-- below. Sent all the way up or down instead, they pass every stop and go on by themselves until they
-- get there or are stopped. A car whose four pads sit under its jacking points goes up with them: it
-- gets a zykeVehicleLift record that carries the lift's motion, is frozen, and is posed from the record
-- by the client that owns it, see client/cars.lua. Back at the bottom it stands on its wheels
-- and is let go of. Other resources shape all of this through the rules of server/rules.lua
-- Metres from the power unit a player may stand to work it
local leverReach = 2.5
-- Metres from a car's middle a player may stand to set the arms under it
local carReach = 6.1
-- Metres a car may have moved from where its arms were set under it before they no longer count
local carSlack = 0.15
-- Metres a lift made again may stand from one that stood there before
local sameLift = 0.05
-- Milliseconds a car is given to settle once it is set down
local settleMs = 300
-- Milliseconds a lift whose maker stopped, or one from before this resource restarted, waits to be made
-- again before a car still on it is set down
local keepMs = 15000

---@type table<integer, ZykeVehicleLift>
local lifts = {}
local lastId = 0
---@type table<integer, LiftCarSet> @ The car each lift's arms were set under, by lift
local cars = {}
---@type table<integer, LiftLever> @ Who works each lift's power unit, by lift
local levers = {}
---@type table<PlayerId, LiftArmSession> @ Who is setting the arms of a lift
local setters = {}
---@type table<integer, integer> @ Counts each lift's motions, so the timer of an older one leaves a newer one be
local motions = {}
---@type table<integer, integer> @ The motion each lift was sent all the way on, which goes on with no button held
local sent = {}
---@type LiftKept[] @ Lifts that went with their maker or with a restart, until they are made again
local kept = {}

local function publish()
    GlobalState.zykeVehicleLifts = lifts
end

---@param liftId integer
---@return ZykeVehicleLift? lift
local function getLift(liftId)
    return type(liftId) == "number" and lifts[liftId] or nil
end

---@param vehicle integer
---@return LiftCar? car @ Nil for a vehicle that is on no lift
local function getRecord(vehicle)
    return Entity(vehicle).state.zykeVehicleLift
end

---@param vehicle integer
---@param liftId integer
---@return LiftCar? car @ Nil unless the vehicle is up on that lift
local function getRecordOn(vehicle, liftId)
    local car = getRecord(vehicle)

    return car and car.liftId == liftId and car or nil
end

---@param vehicle integer
---@param car? LiftCar
local function setRecord(vehicle, car)
    Entity(vehicle).state:set("zykeVehicleLift", car, true)
end

---@param netId? NetId
---@return integer? vehicle
local function getVehicle(netId)
    local vehicle = netId and NetworkGetEntityFromNetworkId(netId)

    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and vehicle or nil
end

---@param lift ZykeVehicleLift
local function unseat(lift)
    lift.netId = nil

    for _, pose in pairs(lift.arms) do
        pose.seated = nil
    end
end

---@param vehicle integer
---@param liftId integer
---@param plyId? PlayerId
---@return LiftCarHookData data
local function getCarData(vehicle, liftId, plyId)
    return {
        source = plyId,
        liftId = liftId,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        modelHash = GetEntityModel(vehicle),
        plate = GetVehicleNumberPlateText(vehicle),
    }
end

-- The car leaves the lift: its record goes, and a car that came down off the pads in the air is put on
-- its wheels by the client that owns it before it is unfrozen. A rule may keep it frozen
---@param vehicle integer
---@param liftId integer
---@param up boolean @ It was off the ground
local function letGo(vehicle, liftId, up)
    setRecord(vehicle, nil)

    local function unfreeze()
        if (DoesEntityExist(vehicle) and not getRecord(vehicle) and not IsLiftCarHeld(vehicle)) then FreezeEntityPosition(vehicle, false) end
    end

    if (up) then SetTimeout(settleMs, unfreeze) else unfreeze() end

    TriggerEvent("zyke_vehiclelifts:OnVehicleLowered", getCarData(vehicle, liftId))
end

-- The car the arms were set under, as long as it still stands where it stood then. A car that has
-- moved off leaves the arms set under nothing
---@param liftId integer
---@return LiftCarSet? car
local function getCar(liftId)
    local car = cars[liftId]
    if (not car) then return nil end

    if (getVehicle(car.netId) == car.vehicle and #(GetEntityCoords(car.vehicle).xy - car.measure.coords.xy) <= carSlack) then return car end

    cars[liftId] = nil

    unseat(lifts[liftId])
    publish()

    return nil
end

---@param lift ZykeVehicleLift
---@return boolean seated @ Every pad sits under its jacking point
local function isSeated(lift)
    for arm = 1, LiftKinds[lift.kind].arms do
        if (not lift.arms[arm].seated) then return false end
    end

    return true
end

---@param lift ZykeVehicleLift
---@return boolean parked @ Every arm is out of the way along its post
local function isParked(lift)
    local kind = LiftKinds[lift.kind]

    for arm = 1, kind.arms do
        if (not kind.isArmParked(lift.arms[arm])) then return false end
    end

    return true
end

---@param lift ZykeVehicleLift
---@param travel number
---@param goal number
---@param now integer
---@return LiftMotion motion
local function newMotion(lift, travel, goal, now)
    return {travel = travel, goal = goal, movedAt = now, speed = lift.speed}
end

-- The carriages arrived where they were going. A car that came down onto its wheels with them is let go of
---@param liftId integer
local function arrive(liftId)
    local lift = lifts[liftId]
    local set = cars[liftId]
    local car = lift and set and getVehicle(set.netId) == set.vehicle and getRecordOn(set.vehicle, liftId)
    if (not car or lift.goal > car.gap) then return end

    letGo(set.vehicle, liftId, false)
end

-- Sends the carriages off from wherever they are toward a goal, for every client and for the car on the pads
---@param liftId integer
---@param goal number
---@param all? boolean @ Sent all the way, so letting go of the buttons or leaving the power unit does not stop them
---@param lowering? boolean @ The lowering handle lets them down, rather than the lock below catching them
local function setMotion(liftId, goal, all, lowering)
    local lift = lifts[liftId]
    local now = GetGameTimer()
    local count = (motions[liftId] or 0) + 1

    motions[liftId] = count
    sent[liftId] = all and count or nil
    lift.travel, lift.goal, lift.movedAt = GetLiftTravel(lift, now), goal, now

    publish()
    PlayLiftMotion(lift, lowering)

    local set = cars[liftId]
    local car = set and getVehicle(set.netId) == set.vehicle and getRecordOn(set.vehicle, liftId)

    if (car) then
        car.motion = newMotion(lift, lift.travel, goal, now)

        setRecord(set.vehicle, car)
    end

    SetTimeout(GetLiftMotionMs(lift) + settleMs, function()
        if (motions[liftId] == count) then arrive(liftId) end
    end)
end

-- The car on the pads leaves the ground with the carriages, from the record of where it stood
---@param liftId integer
---@param set LiftCarSet
---@param plyId PlayerId
local function takeCar(liftId, set, plyId)
    local lift = lifts[liftId]
    local measure = set.measure

    FreezeEntityPosition(set.vehicle, true)

    ---@type LiftCar
    local car = {
        liftId = liftId,
        kind = lift.kind,
        coords = measure.coords,
        rotation = measure.rotation,
        points = measure.points,
        gap = set.gap,
        sill = set.sill,
        hub = set.hub,
        motion = newMotion(lift, lift.travel, lift.goal, lift.movedAt),
        trim = GetLiftTrim(set.netId),
    }

    setRecord(set.vehicle, car)

    TriggerEvent("zyke_vehiclelifts:OnVehicleLifted", getCarData(set.vehicle, liftId, plyId))
end

---@param plyId PlayerId
---@param liftId integer
---@param from number
---@param goal number
---@param set? LiftCarSet
local function runHook(plyId, liftId, from, goal, set)
    local lift = lifts[liftId]

    ---@type LiftHookData
    local data = {
        source = plyId,
        liftId = liftId,
        kind = lift.kind,
        owner = lift.owner,
        coords = lift.coords,
        from = from,
        goal = goal,
        netId = set and set.netId or nil,
        modelHash = set and GetEntityModel(set.vehicle) or nil,
        plate = set and GetVehicleNumberPlateText(set.vehicle) or nil,
    }

    OnLiftMoved(data)
    TriggerEvent("zyke_vehiclelifts:OnLiftMoved", data)
end

-- Asks this resource's gate, then every rule of other resources
---@param plyId PlayerId
---@param liftId integer
---@param action LiftAction
---@param set? LiftCarSet @ The car the work is about
---@param lifted boolean @ The car is up on the pads already
---@return string? notification @ A locale key of this resource
---@return string? text @ The text of another resource's rule
local function askRules(plyId, liftId, action, set, lifted)
    local allowed, reason = CanWorkLift(plyId, liftId, action)
    if (not allowed) then return reason or "actionUnavailable" end

    local lift = lifts[liftId]

    ---@type LiftWorkData
    local data = {
        source = plyId,
        liftId = liftId,
        kind = lift.kind,
        owner = lift.owner,
        action = action,
        vehicle = set and set.vehicle or nil,
        netId = set and set.netId or nil,
        lifted = lifted,
    }

    return nil, GetLiftRefusal(data)
end

---@param stops LiftStop[] @ From the bottom up
---@param travel number
---@param dir 1 | -1
---@param all boolean @ Past every stop to the last one that way
---@return number? goal @ The next stop that way, nil when none lies that way
local function getStopGoal(stops, travel, dir, all)
    local first, last = 1, #stops
    if (dir < 0) then first, last = #stops, 1 end

    local goal

    for i = first, last, dir do
        if ((stops[i].travel - travel) * dir > 0.001) then
            goal = stops[i].travel
            if (not all) then return goal end
        end
    end

    return goal
end

-- A button held at the power unit sends the carriages to the next stop that way, and they stop there
-- by themselves. Sent all the way, they go past every stop to the top or the bottom
---@param plyId PlayerId
---@param liftId integer
---@param dir 1 | -1
---@param all boolean
---@return string? notification @ Why the carriages stay where they are, nil when they set off
---@return string? text @ The same, in another resource's own words
local function pressLever(plyId, liftId, dir, all)
    local lift = lifts[liftId]
    local travel = GetLiftTravel(lift, GetGameTimer())
    local set = getCar(liftId)
    local car = set and getRecordOn(set.vehicle, liftId)

    for _, session in pairs(setters) do
        if (session.liftId == liftId) then return "liftBusy" end
    end

    local onPads = set ~= nil and isSeated(lift)
    if (dir > 0 and not onPads and not isParked(lift)) then return "liftPadsOff" end
    if (dir > 0 and onPads and not car and GetPedInVehicleSeat(set.vehicle, -1) ~= 0) then return "vehicleOccupied" end

    local stops = LiftKinds[lift.kind].getStops(onPads and set or nil)
    local goal = getStopGoal(stops, travel, dir, all)

    if (dir < 0) then
        -- A rule may hold the car up, as when it has nothing left to come down onto
        local held, heldText = nil, nil
        if (goal and car) then held, heldText = GetLiftHold(set.vehicle, stops) end

        if (held and goal < held - 0.001) then
            if (travel <= held + 0.001 and heldText) then return nil, heldText end
            if (travel <= held + 0.001) then return "actionUnavailable" end

            goal = held
        end
    end

    if (not goal) then return nil end

    local notification, text = askRules(plyId, liftId, dir > 0 and "up" or "down", set, car ~= nil)
    if (notification or text) then return notification, text end

    if (dir > 0 and onPads and not car) then
        lift.travel, lift.goal, lift.movedAt = travel, travel, GetGameTimer()

        takeCar(liftId, set, plyId)
    end

    setMotion(liftId, goal, all, dir < 0)
    runHook(plyId, liftId, travel, goal, set)

    return nil
end

-- Where carriages that stand somewhere come to rest: on the lock below, or no lower than a rule holds
-- the car on them
---@param liftId integer
---@param travel number
---@return number goal
local function getRest(liftId, travel)
    local lift = lifts[liftId]
    local goal = GetLiftLockBelow(lift.kind, travel)
    local set = cars[liftId]
    local car = set and getVehicle(set.netId) == set.vehicle and getRecordOn(set.vehicle, liftId)

    if (car) then
        local held = GetLiftHold(set.vehicle, LiftKinds[lift.kind].getStops(car))
        if (held) then goal = math.max(goal, held) end
    end

    return math.min(travel, goal)
end

-- A button let go of between two stops brings the carriages down onto the lock below. Carriages sent
-- all the way go on until they are stopped
---@param liftId integer
---@param halt? boolean @ Stops carriages sent all the way too
local function releaseLever(liftId, halt)
    if (not lifts[liftId]) then return end
    if (not halt and sent[liftId] == motions[liftId]) then return end

    local travel, moving = GetLiftTravel(lifts[liftId], GetGameTimer())
    if (moving) then setMotion(liftId, getRest(liftId, travel)) end
end

---@param plyId PlayerId
local function leaveLever(plyId)
    for liftId, lever in pairs(levers) do
        if (lever.plyId == plyId) then
            levers[liftId] = nil

            releaseLever(liftId)
        end
    end
end

---@param plyId PlayerId
---@param liftId integer
---@return boolean near @ The player stands at the lift's power unit
local function isAtPower(plyId, liftId)
    local ped = GetPlayerPed(plyId)
    local lift = lifts[liftId]
    if (ped == 0 or (lift.bucket and GetPlayerRoutingBucket(plyId) ~= lift.bucket)) then return false end

    return #(GetEntityCoords(ped) - GetLiftWorld(lift, LiftKinds[lift.kind].powerAt)) <= leverReach
end

---@param plyId PlayerId
---@param vehicle integer
---@return boolean near @ The player stands at the car, in its world
local function isAtCar(plyId, vehicle)
    local ped = GetPlayerPed(plyId)
    if (ped == 0 or GetPlayerRoutingBucket(plyId) ~= GetEntityRoutingBucket(vehicle)) then return false end

    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= carReach
end

-- A lift that stood here before takes up where it was: its arms, its car and where its carriages
-- stood, which come to rest on the lock below
---@param lift ZykeVehicleLift
local function restore(lift)
    local found

    for i, entry in ipairs(kept) do
        local old = entry.lift
        if (old.owner == lift.owner and old.kind == lift.kind and old.bucket == lift.bucket and #(old.coords - lift.coords) <= sameLift) then found = i break end
    end

    if (not found) then return end

    local old = table.remove(kept, found).lift
    local now = GetGameTimer()
    local travel = GetLiftTravel(old, now)

    lift.travel, lift.goal, lift.movedAt = travel, travel, now
    lift.arms = old.arms or lift.arms

    -- A car that was up on it is found again by its net id, with the record it was posed from
    local vehicle = getVehicle(old.netId)
    local car = vehicle and getRecordOn(vehicle, old.id)
    if (not car) then unseat(lift) return end

    car.liftId = lift.id
    car.motion = newMotion(lift, travel, travel, now)
    cars[lift.id] = {
        netId = old.netId,
        vehicle = vehicle,
        measure = {coords = car.coords, rotation = car.rotation, points = car.points},
        corners = LiftKinds[lift.kind].getCorners(lift, car) or {},
        gap = car.gap,
        sill = car.sill,
        hub = car.hub,
    }
    lift.netId = old.netId

    setRecord(vehicle, car)
end

-- A car still on a lift that was not made again in time is set down
local function expireKept()
    local now = GetGameTimer()

    for i = #kept, 1, -1 do
        local entry = kept[i]

        if (entry.expiresAt <= now) then
            table.remove(kept, i)

            local vehicle = getVehicle(entry.lift.netId)
            if (vehicle and getRecordOn(vehicle, entry.lift.id)) then letGo(vehicle, entry.lift.id, true) end
        end
    end
end

---@param lift ZykeVehicleLift
local function keep(lift)
    kept[#kept + 1] = {lift = lift, expiresAt = GetGameTimer() + keepMs}

    SetTimeout(keepMs + 100, expireKept)
end

-- Takes a lift out of the world. Anyone at it lets go, and its car is either set down or left up for
-- the lift to be made again
---@param liftId integer
---@param keepCar boolean
local function takeAway(liftId, keepCar)
    local lift = lifts[liftId]
    local set = cars[liftId]

    lifts[liftId], cars[liftId], levers[liftId], motions[liftId], sent[liftId] = nil, nil, nil, nil, nil

    StopLiftSounds(liftId)

    for plyId, session in pairs(setters) do
        if (session.liftId == liftId) then setters[plyId] = nil end
    end

    if (keepCar) then
        keep(lift)
    elseif (set and getVehicle(set.netId) == set.vehicle and getRecordOn(set.vehicle, liftId)) then
        letGo(set.vehicle, liftId, true)
    end

    publish()
end

-- Stands a lift for a resource. The same resource asking again for the same spot in the same bucket gets
-- the lift it has there
---@param options LiftOptions
---@param owner string @ The resource the lift belongs to
---@param placed? boolean @ Placed with the admin command
---@return integer? liftId
function CreateLift(options, owner, placed)
    if (type(options) ~= "table") then return nil end

    local kindName = options.kind or "twopost"
    local kind = LiftKinds[kindName]
    local coords, heading, bucket = options.coords, options.heading or 0.0, options.bucket
    if (not kind or type(coords) ~= "vector3" or type(heading) ~= "number" or heading ~= heading) then return nil end
    if (bucket ~= nil and math.type(bucket) ~= "integer") then return nil end

    for liftId, lift in pairs(lifts) do
        if (lift.owner == owner and lift.kind == kindName and lift.bucket == bucket and #(lift.coords - coords) <= sameLift) then return liftId end
    end

    local arms = {}

    for arm = 1, kind.arms do
        arms[arm] = {swing = kind.parked.swing, reach = kind.parked.reach}
    end

    lastId += 1

    ---@type ZykeVehicleLift
    local lift = {id = lastId, kind = kindName, coords = coords, heading = heading % 360.0, owner = owner, travel = 0.0, goal = 0.0, movedAt = 0, speed = kind.speed, arms = arms, placed = placed, bucket = bucket}
    lifts[lastId] = lift

    restore(lift)
    publish()

    -- Carriages that stopped between two locks come down onto the one below
    local goal = getRest(lastId, lift.travel)
    if (goal < lift.travel - 0.001) then setMotion(lastId, goal) end

    return lastId
end

---@param liftId integer
---@return boolean removed
function RemoveLift(liftId)
    if (not getLift(liftId)) then return false end

    takeAway(liftId, false)

    return true
end

---@return table<integer, ZykeVehicleLift> lifts @ By id
function GetLifts()
    return lifts
end

---@param vehicle integer
---@return boolean lifted @ The vehicle is up on a lift's pads, or on its way there
function IsVehicleOnLift(vehicle)
    return getRecord(vehicle) ~= nil
end

---@param vehicle integer
---@return boolean moving @ The vehicle is on a lift whose carriages are travelling
function IsVehicleOnMovingLift(vehicle)
    local car = getRecord(vehicle)
    if (not car) then return false end

    local _, moving = GetLiftTravel(car.motion, GetGameTimer())

    return moving
end

---@param plyId PlayerId
---@param liftId integer
---@return string? sessionId
---@return string? notification @ Why the player can't work the lift, nil when they can
Z.callback.register("zyke_vehiclelifts:WorkLift", function(plyId, liftId)
    if (not getLift(liftId)) then return nil, "actionUnavailable" end
    if (not isAtPower(plyId, liftId)) then return nil, "tooFar" end

    local lever = levers[liftId]
    if (lever and lever.plyId ~= plyId) then return nil, "liftBusy" end

    leaveLever(plyId)

    local id = Z.createUniqueId()
    levers[liftId] = {plyId = plyId, id = id}

    return id
end)

---@param plyId PlayerId
---@param sessionId string
---@return integer? liftId @ The lift whose power unit the player works in that session
local function getLeverLift(plyId, sessionId)
    for liftId, lever in pairs(levers) do
        if (lever.plyId == plyId and lever.id == sessionId) then return liftId end
    end

    return nil
end

---@param plyId PlayerId
---@param liftId integer
---@param dir -1 | 1
---@param all boolean
local function moveLever(plyId, liftId, dir, all)
    if (dir ~= 1 and dir ~= -1) then return end
    if (not isAtPower(plyId, liftId)) then return Z.notify(plyId, "tooFar") end

    local notification, text = pressLever(plyId, liftId, dir, all)

    if (notification) then
        Z.notify(plyId, notification)
    elseif (text) then
        Z.notify(plyId, text, nil, nil, true, "error")
    end
end

-- 1 for the button that sends the carriages up, -1 for the handle that lets them down and 0 once
-- the player lets go
---@param sessionId string
---@param dir -1 | 0 | 1
RegisterNetEvent("zyke_vehiclelifts:LiftLever", function(sessionId, dir)
    local plyId = source
    local liftId = getLeverLift(plyId, sessionId)
    if (not liftId) then return end
    if (dir == 0) then return releaseLever(liftId) end

    moveLever(plyId, liftId, dir, false)
end)

-- 1 sends the carriages all the way up and -1 all the way down, without a button held. 0 stops them
-- on the lock below
---@param sessionId string
---@param dir -1 | 0 | 1
RegisterNetEvent("zyke_vehiclelifts:SendLift", function(sessionId, dir)
    local plyId = source
    local liftId = getLeverLift(plyId, sessionId)
    if (not liftId) then return end
    if (dir == 0) then return releaseLever(liftId, true) end

    moveLever(plyId, liftId, dir, true)
end)

---@param sessionId string
RegisterNetEvent("zyke_vehiclelifts:LeaveLift", function(sessionId)
    local liftId = getLeverLift(source, sessionId)
    if (not liftId) then return end

    levers[liftId] = nil

    releaseLever(liftId)
end)

---@param plyId PlayerId
---@param liftId integer
---@param netId NetId
---@param measure LiftMeasure @ What the player's client read off the car as it stands on its wheels
---@return string? sessionId
---@return string? notification @ Why the arms can't be set, nil when they can
---@return string? text @ The same, in another resource's own words
Z.callback.register("zyke_vehiclelifts:OpenLiftArms", function(plyId, liftId, netId, measure)
    local lift = getLift(liftId)
    if (not lift) then return nil, "actionUnavailable" end

    local vehicle = type(netId) == "number" and getVehicle(netId) or nil
    if (not vehicle or GetEntityType(vehicle) ~= 2) then return nil, "vehicleGone" end
    if (GetVehicleType(vehicle) ~= "automobile") then return nil, "wrongVehicle" end

    local travel, moving = GetLiftTravel(lift, GetGameTimer())
    if (moving or travel > 0.001) then return nil, "liftNotDown" end

    for other, session in pairs(setters) do
        if (other ~= plyId and session.liftId == liftId) then return nil, "liftBusy" end
    end

    if (not isAtCar(plyId, vehicle) or (lift.bucket and GetEntityRoutingBucket(vehicle) ~= lift.bucket)) then return nil, "tooFar" end
    if (GetPedInVehicleSeat(vehicle, -1) ~= 0) then return nil, "vehicleOccupied" end
    if (#GetEntityVelocity(vehicle) > 0.5) then return nil, "vehicleMoving" end
    if (getRecord(vehicle)) then return nil, "liftBusy" end
    if (not IsLiftMeasureValid(vehicle, measure)) then return nil, "liftNotBetween" end

    local snapped = GetLiftSnap(lift, measure)
    measure = snapped or measure

    local corners, reason = LiftKinds[lift.kind].getCorners(lift, measure)
    if (not corners) then return nil, reason end

    local gap, sill, hub = LiftKinds[lift.kind].getCarHeights(lift, measure, corners)
    local set = {netId = netId, vehicle = vehicle, measure = measure, corners = corners, gap = gap, sill = sill, hub = hub}
    local notification, text = askRules(plyId, liftId, "arms", set, false)
    if (notification or text) then return nil, notification, text end

    cars[liftId] = set
    lift.netId = netId

    -- A car parked a little off is moved square into the middle, where its corners were worked out
    if (snapped) then TriggerClientEvent("zyke_vehiclelifts:SnapLiftCar", NetworkGetEntityOwner(vehicle), netId, snapped.coords, snapped.rotation) end

    -- An arm that was left under a point of this car still sits there
    for arm = 1, LiftKinds[lift.kind].arms do
        local pose = lift.arms[arm]
        pose.seated = LiftKinds[lift.kind].isPadSeated(arm, pose, corners[arm]) or nil
    end

    publish()

    local id = Z.createUniqueId()
    setters[plyId] = {id = id, liftId = liftId}

    return id
end)

-- An arm let go of where the player's hand left it. It sits under its jacking point when its pad is near enough
---@param sessionId string
---@param arm integer
---@param swing number @ Degrees
---@param reach number @ Metres
RegisterNetEvent("zyke_vehiclelifts:SetLiftArm", function(sessionId, arm, swing, reach)
    local session = setters[source]
    if (not session or session.id ~= sessionId) then return end

    local lift = lifts[session.liftId]
    local kind = lift and LiftKinds[lift.kind]
    if (not kind or type(arm) ~= "number" or not math.tointeger(arm) or arm < 1 or arm > kind.arms) then return end
    if (type(swing) ~= "number" or type(reach) ~= "number" or swing ~= swing or reach ~= reach) then return end

    local travel, moving = GetLiftTravel(lift, GetGameTimer())
    if (moving or travel > 0.001) then return end

    local pose = kind.clampArm(swing, reach)
    local set = cars[session.liftId]

    pose.seated = set and kind.isPadSeated(arm, pose, set.corners[arm]) or nil
    lift.arms[arm] = pose

    publish()
end)

---@param sessionId string
RegisterNetEvent("zyke_vehiclelifts:CloseLiftArms", function(sessionId)
    local session = setters[source]
    if (session and session.id == sessionId) then setters[source] = nil end
end)

---@return integer now @ Milliseconds on the server's game timer, which a lift's motion is counted on
Z.callback.register("zyke_vehiclelifts:GetTimer", function()
    return GetGameTimer()
end)

-- A trim set while the car is up reaches every client at once, and the car eases to it from where it
-- stands, see GetLiftTrimNow
---@param vehicle integer
function RefreshLiftTrim(vehicle)
    local car = getRecord(vehicle)
    if (not car) then return end

    local now = GetGameTimer()
    local pitch, height = GetLiftTrimNow(car.trim, now)
    local trim = GetLiftTrim(NetworkGetNetworkIdFromEntity(vehicle)) or {pitch = 0.0, height = 0.0}
    local still = trim.pitch == 0.0 and trim.height == 0.0 and pitch == 0.0 and height == 0.0

    car.trim = not still and {pitch = trim.pitch, height = trim.height, from = {pitch = pitch, height = height}, at = now} or nil

    setRecord(vehicle, car)
end

AddEventHandler("playerDropped", function()
    leaveLever(source)

    setters[source] = nil
end)

-- A resource's lifts go with it. A car up on one stays there for a while, in case the resource is only
-- restarting and makes the lift again. A resource that depends on this one stops just before it does,
-- so the lifts still waiting for their maker go into the global state with the rest, to be waited for
-- again once this resource is back
---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource == ResName) then
        local all = {}

        for liftId, lift in pairs(lifts) do all[liftId] = lift end
        for _, entry in ipairs(kept) do all[entry.lift.id] = entry.lift end

        GlobalState.zykeVehicleLifts = all

        return
    end

    for liftId, lift in pairs(lifts) do
        if (lift.owner == resource) then takeAway(liftId, true) end
    end
end)

---@param options LiftOptions
---@return integer? liftId @ Nil for options that stand no lift
exports("CreateLift", function(options)
    return CreateLift(options, GetInvokingResource() or ResName)
end)

-- Only the resource that made a lift takes it away
---@param liftId integer
---@return boolean removed
exports("RemoveLift", function(liftId)
    local lift = getLift(liftId)
    if (not lift or lift.owner ~= (GetInvokingResource() or ResName)) then return false end

    return RemoveLift(liftId)
end)

---@param liftId integer
---@return ZykeVehicleLift? lift
exports("GetLift", function(liftId)
    return getLift(liftId)
end)

exports("GetLifts", GetLifts)

---@param vehicle integer
---@return LiftCar? car @ The vehicle's record on the pads, nil for one on no lift
exports("GetVehicleLift", function(vehicle)
    return getRecord(vehicle)
end)

exports("IsVehicleOnLift", IsVehicleOnLift)
exports("IsVehicleOnMovingLift", IsVehicleOnMovingLift)

---@param vehicle integer
---@return LiftStopName? stop @ See GetLiftCarStop, nil for a vehicle on no lift
---@return boolean moving
exports("GetVehicleLiftStop", function(vehicle)
    local car = getRecord(vehicle)
    if (not car) then return nil, false end

    return GetLiftCarStop(car, GetGameTimer())
end)

-- The lifts of before a restart wait to be made again, those of shared/lifts.lua and of the
-- admin command first. This runs as the resource loads, before any other resource is told it started
for _, old in pairs(GlobalState.zykeVehicleLifts or {}) do
    kept[#kept + 1] = {lift = old, expiresAt = GetGameTimer() + keepMs}
    lastId = math.max(lastId, old.id or 0)
end

for _, place in ipairs(VehicleLifts or {}) do
    CreateLift(place, ResName)
end

for i = #kept, 1, -1 do
    local old = kept[i] and kept[i].lift
    if (old and old.placed and old.owner == ResName) then CreateLift(old, ResName, true) end
end

publish()

if (next(kept)) then SetTimeout(keepMs + 100, expireKept) end