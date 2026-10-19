-- What the player's client reads off a car as it stands on its wheels, see client/measure.lua,
-- is taken no further than a car goes. A comparison with a number that is not one fails, so those are
-- turned down with the rest
-- Metres a vehicle may stand from where the player's client measured it
local measureSlack = 1.0
-- The furthest a measurement may put an axle along a vehicle, a jacking point out from its middle and a
-- sill off the ground, and the least it may leave between an axle and the jacking point beside it
local mostAlong = 5.0
local mostAcross = 1.6
local mostSill = 1.2
local leastGap = 0.1
-- The furthest from the car's origin its hubs may stand, up or down
local mostHub = 1.5

---@param value number
---@param most number
---@return boolean valid @ A number no further from nothing than that
local function isWithin(value, most)
    return type(value) == "number" and math.abs(value) <= most
end

-- Where a pad meets a sill: on the vehicle's right, between the axles and clear of both
---@param point vector3
---@param frontAxle number
---@param rearAxle number
---@return boolean valid
local function isJackingPoint(point, frontAxle, rearAxle)
    if (type(point) ~= "vector3") then return false end
    if (not isWithin(point.x, mostAcross) or point.x < leastGap or not isWithin(point.z, mostSill)) then return false end

    return isWithin(point.y, mostAlong) and point.y >= rearAxle + leastGap and point.y <= frontAxle - leastGap
end

---@param vehicle integer
---@param measure LiftMeasure
---@return boolean valid @ The measurements could be those of the vehicle as it stands on its wheels
function IsLiftMeasureValid(vehicle, measure)
    if (type(measure) ~= "table" or type(measure.axles) ~= "table" or type(measure.points) ~= "table") then return false end

    local coords, rotation, sill = measure.coords, measure.rotation, measure.sill
    local frontAxle, rearAxle = measure.axles.front, measure.axles.rear
    local front, rear = measure.points.front, measure.points.rear
    if (type(coords) ~= "vector3" or type(rotation) ~= "vector3") then return false end
    if (not isWithin(frontAxle, mostAlong) or not isWithin(rearAxle, mostAlong) or not isWithin(sill, mostSill) or not isWithin(measure.hub, mostHub)) then return false end
    if (not isJackingPoint(front, frontAxle, rearAxle) or not isJackingPoint(rear, frontAxle, rearAxle)) then return false end
    if (front.y < rear.y + leastGap or sill < 0.0) then return false end

    return #(coords - GetEntityCoords(vehicle)) <= measureSlack and #rotation <= 720.0
end