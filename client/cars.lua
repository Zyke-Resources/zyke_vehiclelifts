-- Poses every car up on a lift's pads from its zykeVehicleLift state bag. The client that owns the car poses
-- it, so everyone else sees it through the game's own sync: on its wheels until the pads reach its
-- sills, then level with the carriages, trimmed as other resources asked. Nothing here runs while no
-- car is on a lift, a car at rest is looked at every two seconds, and only one whose carriages travel
-- or whose trim eases is posed every frame
local sweepIntervalMs = 2000
-- Metres the pose of a car at rest may be off before it is set again
local poseSlack = 0.002

---@type table<NetId, LiftTrackedCar> @ Cars that carry the bag
local tracked = {}
local sweeping = false

-- Read from the bag by name, which is there before the car has streamed in
---@param netId NetId
---@return LiftCar? car @ Nil for a car on no lift
local function getCar(netId)
    return GetStateBagValue(("entity:%d"):format(netId), "zykeVehicleLift")
end

---@param vehicle integer
---@param coords vector3
---@param rotation vector3
local function setPose(vehicle, coords, rotation)
    SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z, false, false, false)
    SetEntityRotation(vehicle, rotation.x, rotation.y, rotation.z, 2, false)
end

local update

-- Poses a car every frame for as long as its carriages travel or its trim eases, if this client owns it
---@param netId NetId
---@param entry LiftTrackedCar
local function ease(netId, entry)
    while (tracked[netId] == entry) do
        local car = getCar(netId)
        local vehicle = Z.network.getEntity(netId)
        if (not car or not vehicle) then break end

        local coords, rotation, moving = GetLiftCarPose(car, ServerClock.timer())
        if (not moving) then break end

        if (NetworkHasControlOfEntity(vehicle)) then setPose(vehicle, coords, rotation) end

        Wait(0)
    end

    entry.easing = false

    if (tracked[netId] == entry and not update(netId)) then tracked[netId] = nil end
end

-- Brings this client's pose of a car in line with its bag. Nothing in here yields
---@param netId NetId
---@return boolean follow @ False once the car is off the lift, or gone
function update(netId)
    local entry = tracked[netId]
    local car = getCar(netId)
    local vehicle = Z.network.getEntity(netId)

    if (not car) then
        local was = entry.car

        -- Set down all at once, as when its lift is taken away with it up
        if (was and vehicle and vehicle == entry.vehicle and NetworkHasControlOfEntity(vehicle)) then setPose(vehicle, was.coords, was.rotation) end

        return false
    end

    entry.car = car
    entry.vehicle = vehicle

    -- Net ids are handed out again, and a car that is not here is not posed
    if (not vehicle or entry.easing) then return true end

    local coords, rotation, moving = GetLiftCarPose(car, ServerClock.timer())

    if (moving) then
        entry.easing = true

        CreateThread(function()
            ease(netId, entry)
        end)

        return true
    end

    -- At rest the owner keeps it where the bag has it, which also sets it there for a new owner
    if (NetworkHasControlOfEntity(vehicle)) then
        local off = #(GetEntityCoords(vehicle) - coords) + math.abs(GetEntityRotation(vehicle, 2).x - rotation.x) * 0.02
        if (off > poseSlack) then setPose(vehicle, coords, rotation) end
    end

    return true
end

local function sweep()
    -- A bag's new value is only readable the frame after its handler ran
    Wait(0)

    while (next(tracked)) do
        for netId in pairs(tracked) do
            if (not update(netId)) then tracked[netId] = nil end
        end

        Wait(sweepIntervalMs)
    end

    sweeping = false
end

---@param netId NetId
local function track(netId)
    tracked[netId] = tracked[netId] or {easing = false}

    if (sweeping) then return end

    sweeping = true

    CreateThread(sweep)
end

---@param bagName string
---@param key string
---@param value? LiftCar
AddStateBagChangeHandler("zykeVehicleLift", nil, function(bagName, key, value)
    local netId = tonumber(bagName:match("^entity:(%d+)$"))
    if (not netId) then return end

    -- A trim or a move that was just set eases from where the car stands now, not seconds later
    if (value) then
        ServerClock.atLeast(value.motion.movedAt)
        ServerClock.atLeast(value.trim and value.trim.at)
    end

    local following = sweeping
    local was = tracked[netId] and tracked[netId].car

    track(netId)

    CreateThread(function()
        Wait(0)

        -- A sweep that is already running may be two seconds from its next pass
        if (following and tracked[netId] and not update(netId)) then tracked[netId] = nil end

        -- The pads follow the car on them
        local car = getCar(netId) or was
        if (car) then RedrawLift(car.liftId) end
    end)
end)

-- A car parked a little off, moved square into the middle of a lift by the client that owns it, see
-- GetLiftSnap. Set from the server it would be put down a few centimetres high and twist as it drops
---@param netId NetId
---@param coords vector3
---@param rotation vector3
RegisterNetEvent("zyke_vehiclelifts:SnapLiftCar", function(netId, coords, rotation)
    local vehicle = Z.network.getEntity(netId)
    if (not vehicle or not NetworkHasControlOfEntity(vehicle)) then return end

    setPose(vehicle, coords, rotation)
    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
end)

---@param vehicle integer
---@return LiftCar? car @ The car's record on a lift's pads, read-only
local function getVehicleCar(vehicle)
    return Entity(vehicle).state.zykeVehicleLift
end

exports("GetVehicleLift", getVehicleCar)

---@param vehicle integer
---@return boolean lifted
exports("IsVehicleOnLift", function(vehicle)
    return getVehicleCar(vehicle) ~= nil
end)

---@param vehicle integer
---@return boolean moving @ The vehicle is on a lift whose carriages travel
exports("IsVehicleOnMovingLift", function(vehicle)
    local car = getVehicleCar(vehicle)
    if (not car) then return false end

    local _, moving = GetLiftTravel(car.motion, ServerClock.timer())

    return moving
end)

---@param vehicle integer
---@return LiftStopName? stop @ See GetLiftCarStop, nil for a vehicle on no lift
---@return boolean moving
exports("GetVehicleLiftStop", function(vehicle)
    local car = getVehicleCar(vehicle)
    if (not car) then return nil, false end

    return GetLiftCarStop(car, ServerClock.timer())
end)

CreateThread(function()
    -- Bags set before the resource started fire no handler
    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        local netId = Z.network.getNetId(vehicle)
        if (netId and Entity(vehicle).state.zykeVehicleLift) then track(netId) end
    end
end)