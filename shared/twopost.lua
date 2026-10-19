-- Where a two-post lift's arms reach and how far its carriages travel. In its frame the origin is on
-- the floor midway between the posts and X runs toward the post with the power unit. The sizes are the
-- ones the props are built at, in metres, and have to follow a change made to the props
local settings = Config.Settings.vehiclelifts.kinds.twopost
-- The pivots of the arms on the carriages, across and along from the middle
local pivotX = 1.33
local pivotY = 0.17
-- How near its jacking point a pad has to be to sit under it
local seatReach = 0.05
-- How far a car's middle may stand from the lift's, across and along
local mostOffCentre = vec2(0.45, 1.2)
-- Across and along each arm points from its post: the right front, the right rear, the left front
-- and the left rear
local armSides = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

---@class TwoPostKind: LiftKind
TwoPost = {
    arms = 4,
    -- From the middle across to each post's centre
    postX = 1.60,
    -- How far off the floor the top of an arm and of a pad wound all the way down stand with the
    -- carriages at the bottom
    armTop = 0.080,
    padTop = 0.095,
    -- How far out from its pivot a pad can be drawn, and degrees an arm swings from straight across the
    -- lift to along its post, where it is parked to let a car drive in
    reach = {least = 0.78, most = 1.44},
    swing = 90.0,
    -- Metres of travel between two locks on the posts, and the most the carriages travel
    lockStep = 0.15,
    travel = 2.10,
    -- Where the power unit's UP button is on the right post, and where its user stands, facing back
    -- across the lift
    powerAt = vec3(1.93, 0.0, 1.49),
    operatorAt = vec2(2.30, 0.0),
    -- Half the floor the lift stands on, across and along, with the power unit and the arms parked
    footprint = vec2(1.95, 1.5),
    speed = settings.speed,
}

---@type LiftArm @ Where an arm waits while no car is on it: along its post, drawn all the way in
TwoPost.parked = {swing = TwoPost.swing, reach = TwoPost.reach.least}

LiftKinds.twopost = TwoPost

---@param arm integer @ 1 to TwoPost.arms
---@return integer across @ 1 on the right post, -1 on the left one
---@return integer along @ 1 for a front arm, -1 for a rear one
function TwoPost.getArmSide(arm)
    local side = armSides[arm]

    return side[1], side[2]
end

---@param travel number
---@return vector3 at @ Lift frame, where the locks on the right post catch the carriages at that height
function TwoPost.lockAt(travel)
    return vec3(TwoPost.postX, 0.0, travel + 0.5)
end

---@param arm integer
---@return vector2 pivot @ Lift frame
function TwoPost.getPivot(arm)
    local across, along = TwoPost.getArmSide(arm)

    return vec2(across * pivotX, along * pivotY)
end

-- Straight across the lift at no swing, along the post at the most
---@param arm integer
---@param swing number @ Degrees
---@return vector2 direction @ Lift frame, the way the arm points from its pivot
function TwoPost.getArmDirection(arm, swing)
    local across, along = TwoPost.getArmSide(arm)
    local turn = math.rad(swing)

    return vec2(-across * math.cos(turn), along * math.sin(turn))
end

---@param arm integer
---@param pose LiftArm
---@return vector2 pad @ Lift frame, the middle of the pad
function TwoPost.getPad(arm, pose)
    return TwoPost.getPivot(arm) + TwoPost.getArmDirection(arm, pose.swing) * pose.reach
end

---@param swing number
---@param reach number
---@return LiftArm pose @ As far as the arm swings and draws out
function TwoPost.clampArm(swing, reach)
    return {swing = math.max(0.0, math.min(TwoPost.swing, swing)), reach = math.max(TwoPost.reach.least, math.min(TwoPost.reach.most, reach))}
end

-- The swing and the reach that bring an arm's pad as near to a point as it goes
---@param arm integer
---@param point vector2 @ Lift frame
---@return LiftArm pose
function TwoPost.reachPad(arm, point)
    local across, along = TwoPost.getArmSide(arm)
    local offset = point - TwoPost.getPivot(arm)

    return TwoPost.clampArm(math.deg(math.atan(along * offset.y, -across * offset.x)), #offset)
end

---@param pose LiftArm
---@return boolean parked @ Along its post and drawn all the way in, clear of a car driving in
function TwoPost.isArmParked(pose)
    return pose.swing >= TwoPost.swing - 0.5 and pose.reach <= TwoPost.reach.least + 0.005
end

---@param arm integer
---@param pose LiftArm
---@param corner vector3 @ Lift frame, the jacking point the arm goes under
---@return boolean seated @ The pad is under the point
function TwoPost.isPadSeated(arm, pose, corner)
    return #(TwoPost.getPad(arm, pose) - corner.xy) <= seatReach
end

-- A car stands either way round on a lift, so each arm takes the jacking point on its own corner
---@param lift {coords: vector3, heading: number}
---@param measure LiftMeasure | LiftCar
---@return vector3[]? corners @ Lift frame, the point under each arm, nil for a car that does not stand between the posts
function TwoPost.getCorners(lift, measure)
    local middle = GetLiftPoint(lift, measure.coords)
    if (math.abs(middle.x) > mostOffCentre.x or math.abs(middle.y) > mostOffCentre.y) then return nil end

    local right, forward, up = GetRotationAxes(measure.rotation)
    local corners = {}

    for _, point in pairs(measure.points) do
        for side = -1, 1, 2 do
            local at = GetLiftPoint(lift, measure.coords + right * (point.x * side) + forward * point.y + up * point.z)
            local arm = (at.x > 0.0 and 0 or 2) + (at.y > 0.0 and 1 or 2)
            if (corners[arm]) then return nil end

            corners[arm] = at
        end
    end

    for arm = 1, TwoPost.arms do
        local corner = corners[arm]
        if (not corner or not TwoPost.isPadSeated(arm, TwoPost.reachPad(arm, corner.xy), corner)) then return nil end
    end

    return corners
end

-- What a car on its pads gives the lift: how far the carriages travel before they take it, and how
-- high its sills and its hubs stand off the floor on its wheels
---@param lift {coords: vector3, heading: number}
---@param measure LiftMeasure
---@param corners vector3[]
---@return number gap
---@return number sill
---@return number hub
function TwoPost.getCarHeights(lift, measure, corners)
    local sill = math.huge

    for arm = 1, TwoPost.arms do
        sill = math.min(sill, corners[arm].z)
    end

    local _, _, up = GetRotationAxes(measure.rotation)
    local hub = (measure.coords + up * measure.hub).z - lift.coords.z

    return math.max(0.0, sill - TwoPost.padTop), sill, hub
end

---@param travel number
---@return number locked @ The lock nearest to it
local function toLock(travel)
    return math.max(TwoPost.lockStep, math.min(TwoPost.travel, math.floor(travel / TwoPost.lockStep + 0.5) * TwoPost.lockStep))
end

-- The heights the carriages stop at on their way up and down, each on the lock nearest to it: the
-- bottom, then low, waist and high for a car on the pads, see Config.Settings.vehiclelifts.kinds.twopost, and
-- the top of the posts for an empty lift. A stop that would stand no higher than the one before it is
-- left out
---@param car? {gap: number, sill: number, hub: number}
---@return LiftStop[] stops @ From the bottom up
function TwoPost.getStops(car)
    if (not car) then return {{name = "bottom", travel = 0.0}, {name = "top", travel = TwoPost.travel}} end

    local stops = {{name = "bottom", travel = 0.0}}
    local wanted = {
        {name = "low", travel = car.gap + settings.low - car.sill},
        {name = "waist", travel = car.gap + settings.waist - car.hub},
        {name = "high", travel = car.gap + settings.high - car.sill},
    }

    for _, stop in ipairs(wanted) do
        local travel = toLock(stop.travel)
        if (travel > stops[#stops].travel + 0.001) then stops[#stops + 1] = {name = stop.name, travel = travel} end
    end

    return stops
end