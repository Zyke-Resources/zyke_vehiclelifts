-- What every kind of lift shares, for the server that runs every lift and for each client that stands
-- one. A lift has its own frame: its origin on the floor, X across it, Y the way a car's nose points when
-- it is driven on and Z up. Its carriages travel by the server's game timer from a motion that carries
-- its own speed, so the lift in the zykeVehicleLifts global state and the record of the car on its pads
-- each tell where they stand at any moment. The kinds fill in LiftKinds, see shared/twopost.lua
---@type table<LiftKindName, LiftKind>
LiftKinds = {}

-- The axes of a rotation in the game's order 2: turned about Z, then pitched, then rolled
---@param rotation vector3 @ Degrees
---@return vector3 right
---@return vector3 forward
---@return vector3 up
function GetRotationAxes(rotation)
    local x, y, z = math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z)
    local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
    local right = vec3(cy * cz - sx * sy * sz, cy * sz + sx * sy * cz, -cx * sy)
    local forward = vec3(-sz * cx, cz * cx, sx)

    return right, forward, vec3(right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x)
end

---@param lift {coords: vector3, heading: number}
---@param point vector3 @ Lift frame
---@return vector3 world
function GetLiftWorld(lift, point)
    local turn = math.rad(lift.heading)
    local c, s = math.cos(turn), math.sin(turn)

    return lift.coords + vec3(point.x * c - point.y * s, point.x * s + point.y * c, point.z)
end

---@param lift {coords: vector3, heading: number}
---@param world vector3
---@return vector3 point @ Lift frame
function GetLiftPoint(lift, world)
    local turn = math.rad(lift.heading)
    local c, s = math.cos(turn), math.sin(turn)
    local offset = world - lift.coords

    return vec3(offset.x * c + offset.y * s, offset.y * c - offset.x * s, offset.z)
end

-- Metres two floors may cross and still count as apart, so a row placed edge to edge stands, and how far
-- apart in height two lifts stand on different floors of a building
local overlapSlack = 0.01
local overlapHeight = 3.0

---@param lift {kind: LiftKindName, heading: number}
---@param axis vector2
---@return number reach @ Metres the lift's floor reaches out from its middle along the axis
local function getFloorReach(lift, axis)
    local footprint = LiftKinds[lift.kind].footprint
    local turn = math.rad(lift.heading)
    local c, s = math.cos(turn), math.sin(turn)

    return footprint.x * math.abs(axis.x * c + axis.y * s) + footprint.y * math.abs(axis.y * c - axis.x * s)
end

-- Two lifts whose floors cross in the same routing bucket, where the props of both would stand in each
-- other and a car between the posts of one stands between those of the other. A lift with no bucket
-- stands in every one
---@param one {kind: LiftKindName, coords: vector3, heading: number, bucket?: integer}
---@param other {kind: LiftKindName, coords: vector3, heading: number, bucket?: integer}
---@return boolean overlapping
function DoLiftsOverlap(one, other)
    if (one.bucket and other.bucket and one.bucket ~= other.bucket) then return false end
    if (math.abs(one.coords.z - other.coords.z) > overlapHeight) then return false end

    local offset = other.coords.xy - one.coords.xy

    for _, lift in ipairs({one, other}) do
        local turn = math.rad(lift.heading)
        local c, s = math.cos(turn), math.sin(turn)

        for _, axis in ipairs({vec2(c, s), vec2(-s, c)}) do
            local apart = math.abs(offset.x * axis.x + offset.y * axis.y)
            if (apart >= getFloorReach(one, axis) + getFloorReach(other, axis) - overlapSlack) then return false end
        end
    end

    return true
end

-- A car parked a little off, moved to stand square in the middle of the lift, either way round: its
-- jacking points even about the lift's origin and its nose along the lift's Y. The client and the
-- server each come to the same pose from the same measurements
---@param lift {coords: vector3, heading: number}
---@param measure LiftMeasure
---@return LiftMeasure? snapped @ Nil for a car further off than Config.Settings.vehiclelifts.snap allows, or already square
function GetLiftSnap(lift, measure)
    local snap = Config.Settings.vehiclelifts.snap
    if (not snap or snap.distance <= 0.0 or snap.angle <= 0.0) then return nil end

    local turn = (measure.rotation.z - lift.heading) % 360.0
    local square = (turn > 90.0 and turn < 270.0) and 180.0 or 0.0
    local off = (turn - square + 180.0) % 360.0 - 180.0
    if (math.abs(off) > snap.angle) then return nil end

    -- Halfway between the jacking points along the car, before and after the move
    local along = (measure.points.front.y + measure.points.rear.y) * 0.5
    local origin = GetLiftPoint(lift, measure.coords)
    local now, wanted = math.rad(turn), math.rad(square)
    local middle = origin.xy + vec2(-math.sin(now), math.cos(now)) * along
    if (#middle > snap.distance) then return nil end
    if (#middle < 0.001 and math.abs(off) < 0.05) then return nil end

    local snapped = Z.table.copy(measure)
    local at = -vec2(-math.sin(wanted), math.cos(wanted)) * along
    snapped.coords = GetLiftWorld(lift, vec3(at.x, at.y, origin.z))
    snapped.rotation = vec3(measure.rotation.x, measure.rotation.y, (lift.heading + square) % 360.0)

    return snapped
end

-- Where the carriages stand at a moment, on a motion that set off from where they stood at its start
-- toward its goal
---@param motion LiftMotion
---@param now? integer @ Milliseconds on the server's game timer, nil on a client that does not know it yet
---@return number travel @ Metres up from the bottom
---@return boolean moving
function GetLiftTravel(motion, now)
    local span = motion.goal - motion.travel
    if (math.abs(span) < 0.0001 or not now) then return motion.goal, false end

    local done = math.max(0.0, (now - motion.movedAt) / 1000.0 * motion.speed)
    if (done >= math.abs(span)) then return motion.goal, false end

    return motion.travel + (span > 0.0 and done or -done), true
end

---@param motion LiftMotion
---@return integer ms @ Milliseconds from its start the motion takes
function GetLiftMotionMs(motion)
    return math.ceil(math.abs(motion.goal - motion.travel) / motion.speed * 1000.0)
end

---@param kindName LiftKindName
---@param travel number
---@return number locked @ The highest lock at or below it, the bottom below the first
function GetLiftLockBelow(kindName, travel)
    local step = LiftKinds[kindName].lockStep

    return math.max(0.0, math.floor(travel / step + 0.0001) * step)
end

-- The stop a car on a lift's pads stands at, or has passed on its way up: low as soon as the carriages
-- reach low's lock and until they reach waist's, and so on. Between the bottom and low it is none
---@param car LiftCar
---@param now? integer @ Milliseconds on the server's game timer
---@return LiftStopName? stop
---@return boolean moving
function GetLiftCarStop(car, now)
    local travel, moving = GetLiftTravel(car.motion, now)
    local reached

    for _, stop in ipairs(LiftKinds[car.kind].getStops(car)) do
        if (stop.name ~= "bottom" and travel >= stop.travel - 0.001) then reached = stop.name end
    end

    return reached, moving
end

-- How fast a car's pose follows a trim set while it is up: degrees of pitch and metres of height a
-- second. Over its first few centimetres off the pads' first touch the trim comes in with the height
local trimRate = {pitch = 1.5, height = 0.05}
local trimLift = 0.05

-- What a trim comes to at a moment, on its way from the one before it
---@param trim? LiftCarTrim
---@param now? integer @ Milliseconds on the server's game timer
---@return number pitch @ Degrees
---@return number height @ Metres
---@return boolean easing @ Still on its way
function GetLiftTrimNow(trim, now)
    if (not trim) then return 0.0, 0.0, false end

    local from = trim.from
    if (not from or not trim.at or not now) then return trim.pitch, trim.height, false end

    local seconds = math.max(math.abs(trim.pitch - from.pitch) / trimRate.pitch, math.abs(trim.height - from.height) / trimRate.height)
    local share = seconds > 0.0 and math.max(0.0, math.min(1.0, (now - trim.at) / 1000.0 / seconds)) or 1.0

    return from.pitch + (trim.pitch - from.pitch) * share, from.height + (trim.height - from.height) * share, share < 1.0
end

-- Where a car on a lift's pads stands at a moment: on its wheels until the pads reach its sills, then
-- up level with them, pitched and raised by its trim
---@param car LiftCar
---@param now? integer @ Milliseconds on the server's game timer
---@return vector3 coords
---@return vector3 rotation @ Degrees, in the game's order 2
---@return boolean moving @ The carriages travel or the trim eases
function GetLiftCarPose(car, now)
    local travel, moving = GetLiftTravel(car.motion, now)
    local up = math.max(0.0, travel - car.gap)
    local pitch, height, easing = GetLiftTrimNow(car.trim, now)
    local share = math.min(1.0, up / trimLift)

    return car.coords + vec3(0.0, 0.0, up + height * share), car.rotation + vec3(pitch * share, 0.0, 0.0), moving or easing
end