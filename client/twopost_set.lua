-- A two-post lift's props and where each stands for a state of the lift: the posts and the floor plate
-- where the lift was put, the carriages as high as they have travelled, the arms swung and drawn out to
-- where they were set with a pad on each, wound up to meet the sill of the car it is under, and the
-- power unit's lowering handle held open while the carriages come down. Everything is in the lift
-- frame, see shared/lift.lua. Every size is the one the props are built at, in metres, and has to
-- follow a change made to the props
LiftSets = LiftSets or {}

---@class TwoPostSet: LiftSet
TwoPostSet = {}

LiftSets.twopost = TwoPostSet

TwoPostSet.models = {
    post = "zyke_vehiclelifts_twopost_post",
    carriage = "zyke_vehiclelifts_twopost_carriage",
    arm = "zyke_vehiclelifts_twopost_arm",
    ext = "zyke_vehiclelifts_twopost_arm_ext",
    pad = "zyke_vehiclelifts_twopost_pad",
    plate = "zyke_vehiclelifts_twopost_plate",
    power = "zyke_vehiclelifts_twopost_power",
    handle = "zyke_vehiclelifts_twopost_handle",
    release = "zyke_vehiclelifts_twopost_release",
}

-- The props people walk into and a car rolls over keep their collision
TwoPostSet.solid = {post = true, plate = true, power = true}
-- The most a pad's screw winds it up off its socket
local windMost = 0.10
-- How far the extension's top stands below the arm's, and the pad's socket on it above the arm's top
local extDrop = 0.010
local socketRise = 0.001
-- Where the power unit meets the right post's outer face, and in its own frame the turn axes of its
-- lowering handle, about its Y, and of the lock release lever, about its X
local powerAt = vec3(TwoPost.postX + 0.14, 0.0, 1.30)
local handleAt = vec3(0.10, 0.091, 0.0)
local releaseAt = vec3(0.03, -0.128, 0.19)
-- Degrees the handle is pushed down and the release lever pulled down while the carriages come down,
-- the most each one travels
local handleOpen = 35.0
local releaseOpen = 40.0
-- How far from the middle a car may stand to count as between the posts, across and along
local between = vec2(TwoPost.postX - 0.5, 2.0)

-- The car on a lift's pads as the pads are drawn: the way it faces, and how far each pad is wound up
-- to meet its sill as the car stands now, trimmed or not
---@param lift ZykeVehicleLift
---@param car LiftCar
---@param now? integer @ Milliseconds on the server's game timer
---@return LiftPads? pads @ Nil for a car its arms do not reach
function TwoPostSet.pads(lift, car, now)
    local _, rotation, moving = GetLiftCarPose(car, now)
    local corners = TwoPost.getCorners(lift, {coords = car.coords, rotation = rotation, points = car.points})
    if (not corners) then return nil end

    local lowest = math.huge

    for arm = 1, TwoPost.arms do
        lowest = math.min(lowest, corners[arm].z)
    end

    local winds = {}

    for arm = 1, TwoPost.arms do
        winds[arm] = math.min(windMost, corners[arm].z - lowest)
    end

    return {yaw = car.rotation.z - lift.heading, winds = winds, moving = moving}
end

---@param travel number @ Metres the carriages stand up
---@param arms LiftArm[]
---@param pads? LiftPads @ The car on the pads, nil for none
---@param lowering boolean @ The carriages are on their way down
---@return LiftPiece[] pieces
function TwoPostSet.pieces(travel, arms, pads, lowering)
    local models = TwoPostSet.models
    local pieces = {}

    for post = 1, 2 do
        local side = post == 1 and 1.0 or -1.0
        local yaw = post == 1 and 0.0 or 180.0

        pieces[#pieces + 1] = {key = "post" .. post, model = models.post, at = vec3(side * TwoPost.postX, 0.0, 0.0), yaw = yaw}
        pieces[#pieces + 1] = {key = "carriage" .. post, model = models.carriage, at = vec3(side * TwoPost.postX, 0.0, travel), yaw = yaw}
    end

    for arm = 1, TwoPost.arms do
        local pose = arms[arm] or TwoPost.parked
        local direction = TwoPost.getArmDirection(arm, pose.swing)
        local yaw = math.deg(math.atan(-direction.x, direction.y))
        local pivot = TwoPost.getPivot(arm)
        local pad = pivot + direction * pose.reach
        local top = travel + TwoPost.armTop
        local wind = pads and pose.seated and pads.winds[arm] or 0.0

        pieces[#pieces + 1] = {key = "arm" .. arm, model = models.arm, at = vec3(pivot.x, pivot.y, top), yaw = yaw}
        pieces[#pieces + 1] = {key = "ext" .. arm, model = models.ext, at = vec3(pad.x, pad.y, top - extDrop), yaw = yaw}
        pieces[#pieces + 1] = {key = "pad" .. arm, model = models.pad, at = vec3(pad.x, pad.y, top + socketRise + wind), yaw = pads and pads.yaw or yaw}
    end

    pieces[#pieces + 1] = {key = "plate", model = models.plate, at = vec3(0.0, 0.0, 0.0), yaw = 0.0}
    pieces[#pieces + 1] = {key = "power", model = models.power, at = powerAt, yaw = 0.0}
    pieces[#pieces + 1] = {key = "handle", model = models.handle, at = powerAt + handleAt, yaw = 0.0, roll = lowering and handleOpen or 0.0}
    pieces[#pieces + 1] = {key = "release", model = models.release, at = powerAt + releaseAt, yaw = 0.0, pitch = lowering and releaseOpen or 0.0}

    return pieces
end

---@param point vector3 @ Lift frame, the middle of a car
---@return boolean between @ The car stands between the posts
function TwoPostSet.isBetween(point)
    return math.abs(point.x) <= between.x and math.abs(point.y) <= between.y
end