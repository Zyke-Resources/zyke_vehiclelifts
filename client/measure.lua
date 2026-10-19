-- What a lift's arms are set by, read off a car as it stands on its wheels: where its axles are, its
-- jacking points under the sills behind the front wheel and ahead of the rear one, and how high its
-- sills and hubs stand. The server takes it no further than a car goes, see server/measure.lua
-- A sill is looked for from the ground up to the top of the tyre beside it, from this far outside the
-- wheels in, a probe every few centimetres, so a lifted truck is reached as well as a low car
local sillOut = 0.25
local sillStep = 0.03
local sillSteps = 16
-- The sill is the lowest of the body across the probes, and its edge the outermost probe no more than
-- this many metres above that. Flares, door skins and mirrors all hang higher than it
local sillRise = 0.05
-- Metres in from the edge of the body a pad goes, and how far from the wheel beside it
local pointInset = 0.06
local pointGap = 0.18
-- What a wheel is taken to measure when the ground under it is not found
local wheelRadius = 0.34

---@param vehicle integer
---@param bone string
---@return vector3? offset @ Vehicle space, nil for a model without the bone
local function getBoneOffset(vehicle, bone)
    local index = GetEntityBoneIndexByName(vehicle, bone)
    if (index == -1) then return nil end

    local at = GetWorldPositionOfEntityBone(vehicle, index)

    return GetOffsetFromEntityGivenWorldCoords(vehicle, at.x, at.y, at.z)
end

---@param vehicle integer
---@param offset vector3 @ Vehicle space
---@return number? height @ Metres the spot is off the ground, nil where no ground is found
local function getHeight(vehicle, offset)
    local at = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
    local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, at.z, false)

    return found and at.z - groundZ or nil
end

-- The underside of the body straight above a spot on the ground
---@param vehicle integer
---@param x number @ Vehicle space
---@param y number
---@param reach number @ Metres off the ground the probe goes up to
---@return vector3? at @ Vehicle space, nil where nothing of the vehicle is overhead
---@return number? height @ Metres that is off the ground
local function probeSill(vehicle, x, y, reach)
    local from = GetOffsetFromEntityInWorldCoords(vehicle, x, y, 0.0)
    local found, groundZ = GetGroundZFor_3dCoord(from.x, from.y, from.z, false)
    if (not found) then return nil end

    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, groundZ + 0.02, from.x, from.y, groundZ + reach, 2, PlayerPedId(), 0)
    local _, hit, at, _, entity = GetShapeTestResult(handle)
    if (hit ~= 1 or entity ~= vehicle) then return nil end

    return GetOffsetFromEntityGivenWorldCoords(vehicle, at.x, at.y, at.z), at.z - groundZ
end

-- A pad goes under the sill beside a wheel, on the side of it the other axle is on. The model's box
-- takes in its mirrors, so the edge of the body is found from below, from outside the wheels in
---@param vehicle integer
---@param wheel vector3 @ Vehicle space, where the wheel's bone is
---@param toward 1 | -1 @ The way along the vehicle the other axle lies
---@return vector3? at @ Vehicle space, on the vehicle's right
---@return number? height @ Metres that is off the ground
local function findPoint(vehicle, wheel, toward)
    local radius = math.max(0.2, math.min(0.6, getHeight(vehicle, wheel) or wheelRadius))
    local y = wheel.y + toward * (radius + pointGap)
    local out = math.abs(wheel.x) + sillOut
    local reach = radius * 2
    local hits, lowest = {}, math.huge

    for step = 0, sillSteps do
        local x = out - step * sillStep
        local at, height = probeSill(vehicle, x, y, reach)

        if (at) then
            hits[#hits + 1] = {x = x, at = at, height = height}
            lowest = math.min(lowest, height)
        end
    end

    for _, hit in ipairs(hits) do
        if (hit.height <= lowest + sillRise) then
            local at, height = probeSill(vehicle, hit.x - pointInset, y, reach)
            if (at and height <= lowest + sillRise) then return at, height end

            return hit.at, hit.height
        end
    end

    return nil
end

---@param vehicle integer
---@return LiftMeasure? measure @ Nil for a car with nowhere under its sills to set a pad
function MeasureLiftCar(vehicle)
    local frontWheel = getBoneOffset(vehicle, "wheel_lf")
    local rearWheel = getBoneOffset(vehicle, "wheel_lr")
    if (not frontWheel or not rearWheel) then return nil end

    local front, frontHeight = findPoint(vehicle, frontWheel, -1)
    local rear, rearHeight = findPoint(vehicle, rearWheel, 1)
    if (not front or not rear) then return nil end

    ---@type LiftMeasure
    return {
        coords = GetEntityCoords(vehicle),
        rotation = GetEntityRotation(vehicle, 2),
        axles = {front = frontWheel.y, rear = rearWheel.y},
        points = {front = front, rear = rear},
        sill = math.min(frontHeight, rearHeight),
        hub = frontWheel.z,
    }
end