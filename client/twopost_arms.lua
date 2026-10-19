-- Setting a two-post lift's arms under a car that stands between its posts. The player kneels where
-- they stand and the view looks down at the arm that comes in from its post under the car at a corner.
-- The cursor is on the screen, and the left mouse button held on the pad drags it over the floor to
-- where the cursor points: the arm swings on its pin and its extension slides in and out, as
-- far as each goes. A pad brought near the car's jacking point, marked by a ring behind a front wheel or
-- ahead of a rear one, drops onto it with a clunk and stays there until it is drawn well away again, and
-- an arm swung back along its post and drawn all the way in parks. A and D go round the corners. The
-- server keeps each arm as it is let go of, see server/lifts.lua, and the lift only takes the
-- car with all four pads under it
local fov = 50.0
local cursors = {aim = 1, grab = 3, drag = 4}
-- How fast a held pad follows the cursor, and how near the cursor a pad has to be to be taken
local followRate = 14.0
local grabReach = 0.22
-- A pad brought this near its point drops onto it, and one on it stays until the hand is this far off
local seatSnap = 0.15
local seatLeave = 0.28
-- Degrees an arm is swung back along its post, and metres it is drawn in from all the way, at which it parks
local parkSwing = 75.0
local parkReach = 0.12
-- The ring under the jacking point, a little off the floor so it does not flicker. The ground can stand
-- above the lift's floor, so it is looked for from this high over the floor
local markHeight = 0.02
local markSearch = 0.5
local markColours = {free = {245, 124, 0, 190}, seated = {80, 200, 90, 190}}
-- Metres from a carriage, or from the car in the target menu, the arms are offered
local armsReach = 2.5
-- Metres off the floor the arms are marked on the carriages, and the ray that finds the car between the
-- posts goes across
local pointHeight = 0.35
local rayHeight = 0.7
local kneelAnim = {dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer"}
-- Stand-ins until the lifts have sounds of their own
local seatSound = {name = "Drill_Pin_Break", set = "DLC_HEIST_FLEECA_SOUNDSET"}
local parkSound = {name = "NAV_UP_DOWN", set = "HUD_FRONTEND_DEFAULT_SOUNDSET"}
-- The corners in the order A and D go round them: right front, right rear, left rear, left front
local ring = {1, 2, 4, 3}
local frameZ = vec3(0.0, 0.0, 1.0)

---@param game LiftArmsGame
---@param result LiftSceneResult
local function finish(game, result)
    if (not game.result) then game.result = result end
end

-- From above and out past the corner, where the whole arm and the ring under the jacking point are in view
---@param game LiftArmsGame
---@return LiftView view @ Lift frame
local function getView(game)
    local corner = game.corners[game.arm]
    local across, along = TwoPost.getArmSide(game.arm)

    return {at = vec3(corner.x + across * 1.6, corner.y + along * 1.2, 1.35), target = vec3(corner.x + across * 0.2, corner.y - along * 0.3, 0.1)}
end

-- The player kneels where they stand, turned to the corner the scene opens at, for everyone else to see
---@param game LiftArmsGame
local function kneel(game)
    local ped = game.scene.ped
    local facing = GetLiftWorld(game.lift, game.corners[game.arm]) - GetEntityCoords(ped)
    local heading = math.deg(math.atan(-facing.x, facing.y)) % 360.0

    CreateThread(function()
        local loaded = Z.loadDict(kneelAnim.dict, true, 3000)

        -- The scene may have ended while the dictionary loaded
        if (not loaded or game.result) then return end

        SetEntityHeading(ped, heading)
        TaskPlayAnim(ped, kneelAnim.dict, kneelAnim.clip, 4.0, 4.0, -1, 1, 0.0, false, false, false)
    end)
end

---@param game LiftArmsGame
---@param step 1 | -1 @ The way round the corners
local function stepCorner(game, step)
    if (game.holding) then return end

    local at = 1

    for i = 1, #ring do
        if (ring[i] == game.arm) then at = i end
    end

    game.arm = ring[(at - 1 + step) % #ring + 1]
end

---@param game LiftArmsGame
local function setButtons(game)
    local context = game.holding and "hold" or "free"
    if (context == game.context) then return end

    game.context = context

    -- The loop reads the mouse button itself to follow the hold
    local rows = {{label = T("control:moveArm"), key = "LEFTMOUSE", func = function() end}}

    if (not game.holding) then
        rows[#rows + 1] = {label = T("control:nextArm"), key = {"A", "D"}, func = function(key) stepCorner(game, key == "A" and 1 or -1) end}
    end

    rows[#rows + 1] = {label = T("control:leave"), key = "ESC", hiddenKey = "BACKSPACE", func = function() finish(game, "cancelled") end}
    game.keybinds = rows
    -- The scene hides them as it closes, however it ends
    game.scene.keybinds = rows

    LiftKeybinds.show(rows, {title = T("title:setArms")})
end

---@param sound {name: string, set: string}
---@param at vector3 @ World
local function playAt(sound, at)
    PlaySoundFromCoord(-1, sound.name, at.x, at.y, at.z, sound.set, false, 0, false)
end

-- The arm stays where the hand left it, and the server is told
---@param game LiftArmsGame
local function letGo(game)
    local pose = game.arms[game.arm]

    game.holding = false

    TriggerServerEvent("zyke_vehiclelifts:SetLiftArm", game.sessionId, game.arm, pose.swing, pose.reach)
end

-- The arm follows the hand on its pin and its slide, onto the jacking point or back to its park
---@param game LiftArmsGame
---@param dt number
local function drag(game, dt)
    local arm = game.arm
    local pose = game.arms[arm]
    local corner = game.corners[arm]
    local goal = game.goal

    -- A pad on its point stays there until the hand has drawn well away from it
    if (pose.seated and #(goal - corner.xy) <= seatLeave) then return end

    local seated = #(goal - corner.xy) <= seatSnap
    local wanted = TwoPost.reachPad(arm, goal)
    local parking = wanted.swing >= parkSwing and wanted.reach <= TwoPost.reach.least + parkReach
    local moved

    -- A parked pad follows the hand out, and only drops back into its park once the hand has had it out
    if (not parking) then game.outOfPark = true end

    if (seated) then
        moved = TwoPost.reachPad(arm, corner.xy)
        moved.seated = true
    elseif (parking and game.outOfPark) then
        moved = {swing = TwoPost.parked.swing, reach = TwoPost.parked.reach}
    else
        local pad = TwoPost.getPad(arm, pose)

        moved = TwoPost.reachPad(arm, pad + (goal - pad) * (1.0 - math.exp(-dt * followRate)))
    end

    if (seated and not pose.seated) then playAt(seatSound, GetLiftWorld(game.lift, vec3(corner.x, corner.y, TwoPost.padTop))) end
    if (TwoPost.isArmParked(moved) and not TwoPost.isArmParked(pose)) then PlaySoundFrontend(-1, parkSound.name, parkSound.set, true) end

    game.arms[arm] = moved

    SetLiftArmsHeld(game.liftId, game.arms)
end

-- The button takes the pad of the arm in view when the cursor is on it
---@param game LiftArmsGame
---@param dt number
local function updateInput(game, dt)
    local scene = game.scene
    local point = LiftScene.rayOnPlane(scene, LiftScene.cursorRay(scene, LiftScene.cursor()), frameZ * TwoPost.padTop, frameZ)
    local pad = TwoPost.getPad(game.arm, game.arms[game.arm])
    local near = point ~= nil and #(point.xy - pad) <= grabReach

    setButtons(game)
    LiftKeybinds.handle(game.keybinds)
    SetMouseCursorActiveThisFrame()
    SetMouseCursorStyle(game.holding and cursors.drag or (near and cursors.grab or cursors.aim))

    if (game.result) then return end

    if (not game.holding) then
        if (near and IsDisabledControlJustPressed(0, 24)) then
            game.holding = true
            game.goal = pad
            game.outOfPark = not TwoPost.isArmParked(game.arms[game.arm])
        end

        return
    end

    if (not IsDisabledControlPressed(0, 24)) then return letGo(game) end

    -- A cursor past where the arm goes has the pad stop at the arm's limit
    if (point) then game.goal = TwoPost.getPad(game.arm, TwoPost.reachPad(game.arm, point.xy)) end

    drag(game, dt)
end

-- Where the ring under a jacking point goes: on the lift's floor, or on the ground where any of it
-- stands higher, so the ring is never sunk out of sight
---@param game LiftArmsGame
---@param arm integer
---@return vector3 at
local function getMark(game, arm)
    local corner = game.corners[arm]
    local floorZ = GetLiftWorld(game.lift, vec3(corner.x, corner.y, 0.0)).z
    local topZ = floorZ

    for _, offset in ipairs({vec2(0.0, 0.0), vec2(seatSnap, 0.0), vec2(-seatSnap, 0.0), vec2(0.0, seatSnap), vec2(0.0, -seatSnap)}) do
        local probe = GetLiftWorld(game.lift, vec3(corner.x + offset.x, corner.y + offset.y, markSearch))
        local found, groundZ = GetGroundZFor_3dCoord(probe.x, probe.y, probe.z, false)

        if (found and groundZ > topZ and groundZ < probe.z) then topZ = groundZ end
    end

    return GetLiftWorld(game.lift, vec3(corner.x, corner.y, topZ - floorZ + markHeight))
end

-- A ring under the jacking point the arm in view goes to, as wide as the pad drops onto it from
---@param game LiftArmsGame
local function markPoint(game)
    game.marks[game.arm] = game.marks[game.arm] or getMark(game, game.arm)

    local at = game.marks[game.arm]
    local colour = game.arms[game.arm].seated and markColours.seated or markColours.free
    local size = seatSnap * 2.0

    DrawMarker(25, at.x, at.y, at.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, size, colour[1], colour[2], colour[3], colour[4], false, false, 2, false, nil, nil, false)
end

---@param game LiftArmsGame
local function runFrame(game)
    local dt = math.max(0.001, math.min(0.1, GetFrameTime()))

    LiftScene.tick(game.scene, getView(game), dt)

    if (game.ready) then
        markPoint(game)
        updateInput(game, dt)
    end
end

---@param session LiftSceneSession
---@param liftId integer
---@param vehicle integer
---@param sessionId string
---@param corners vector3[]
---@param arm integer @ The corner the scene opens at
---@param left {arms?: LiftArm[]} @ Gets the arms as the scene leaves them
---@return LiftSceneResult result
local function playArms(session, liftId, vehicle, sessionId, corners, arm, left)
    local lift, plate = GetLift(liftId), GetLiftPlate(liftId)
    if (not lift or not plate) then return "unavailable" end

    local arms = {}

    for index = 1, TwoPost.arms do
        local pose = lift.arms[index] or TwoPost.parked

        arms[index] = {swing = pose.swing, reach = pose.reach, seated = TwoPost.isPadSeated(index, pose, corners[index]) or nil}
    end

    ---@type LiftArmsGame
    local game = {
        liftId = liftId,
        lift = lift,
        sessionId = sessionId,
        corners = corners,
        marks = {},
        arms = arms,
        arm = arm,
        holding = false,
    }

    -- The plate stands at the lift's origin and turned its way, so the scene's frame is the lift's
    local scene = LiftScene.create(plate, PlayerPedId(), getView(game), fov)

    session.scene = scene
    game.scene = scene

    SetLiftArmsHeld(liftId, arms)
    kneel(game)
    setButtons(game)
    LiftScene.openCamera(scene)
    SetCursorLocation(0.5, 0.5)

    local ped = scene.ped
    local readyAt = GetGameTimer() + LiftScene.easeTime()
    while (GetGameTimer() < readyAt) do
        runFrame(game)

        Wait(0)
    end

    game.ready = true

    while (not game.result) do
        if (not DoesEntityExist(vehicle) or IsEntityDead(ped) or IsPedRagdoll(ped) or not GetLift(liftId)) then finish(game, "interrupted") end

        runFrame(game)

        Wait(0)
    end

    if (game.holding) then letGo(game) end

    left.arms = game.arms

    return game.result
end

---@param arms LiftArm[]
---@param corners vector3[]
---@return boolean seated @ Every pad sits under its jacking point
local function isSeated(arms, corners)
    for arm = 1, TwoPost.arms do
        if (not TwoPost.isPadSeated(arm, arms[arm], corners[arm])) then return false end
    end

    return true
end

---@param vehicle integer
---@return integer? liftId @ The two-post lift, all the way down, the vehicle stands on its wheels between the posts of
local function getLiftFor(vehicle)
    if (IsWorkingLift() or Entity(vehicle).state.zykeVehicleLift ~= nil) then return nil end

    local liftId = FindLiftUnder(vehicle)
    local lift = liftId and GetLift(liftId)
    if (not lift or lift.kind ~= "twopost") then return nil end

    local travel, moving = GetLiftTravelNow(lift)
    if (moving or travel > 0.001) then return nil end

    return liftId
end

---@param vehicle integer
local function setArms(vehicle)
    local liftId = getLiftFor(vehicle)
    if (not liftId or IsPlayerBusy(vehicle)) then Z.notify("actionUnavailable") return end

    local lift = GetLift(liftId)
    local netId = Z.network.getNetId(vehicle)
    if (not netId) then return end

    local allowed, reason = CanWorkLift(liftId, "arms")
    if (not allowed) then Z.notify(reason or "actionUnavailable") return end

    local measure = MeasureLiftCar(vehicle)
    if (not measure) then Z.notify("liftNoPoint") return end

    -- The server moves a car parked a little off to the same pose, see GetLiftSnap
    local corners = TwoPost.getCorners(lift, GetLiftSnap(lift, measure) or measure)
    if (not corners) then Z.notify("liftNotBetween") return end

    local sessionId, notification, text = Z.callback.await("zyke_vehiclelifts:OpenLiftArms", liftId, netId, measure)

    if (not sessionId and text) then Z.notify(text, nil, nil, true, "error") return end
    if (not sessionId) then Z.notify(notification or "actionUnavailable") return end

    -- The scene opens at the corner the player stands nearest to
    local at = GetLiftPoint(lift, GetEntityCoords(PlayerPedId()))
    local arm = (at.x > 0.0 and 0 or 2) + (at.y > 0.0 and 1 or 2)
    local left = {}
    local result = LiftScene.run(playArms, liftId, vehicle, sessionId, corners, arm, left)

    SetLiftArmsHeld(liftId, nil)
    TriggerServerEvent("zyke_vehiclelifts:CloseLiftArms", sessionId)
    -- The kneel would keep the player from moving
    ClearPedTasks(PlayerPedId())

    if (result == "interrupted") then Z.notify("interrupted") return end

    -- The server's copy of the last arm may not be here yet, so the scene's own is told of
    if (result == "cancelled" and left.arms and isSeated(left.arms, corners)) then Z.notify("liftArmsSet") end
end

-- A ray across the lift from post to post, which only a vehicle stops
---@param lift ZykeVehicleLift
---@return integer? vehicle
local function findCarBetween(lift)
    local from = GetLiftWorld(lift, vec3(-TwoPost.postX, 0.0, rayHeight))
    local to = GetLiftWorld(lift, vec3(TwoPost.postX, 0.0, rayHeight))
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 2, 0, 4)
    local _, _, _, _, entity = GetShapeTestResult(ray)
    if (not entity or entity == 0 or not IsEntityAVehicle(entity)) then return nil end

    return entity
end

-- Both carriages of every lift near the player that a car stands between the posts of, see
-- client/interactions.lua
---@param add fun(point: LiftInteractionPoint)
---@param pedCoords vector3
RegisterLiftInteractionPoints(function(add, pedCoords)
    local liftIds = GetShownLiftsNear(pedCoords)

    for i = 1, #liftIds do
        local liftId = liftIds[i]
        local lift = GetLift(liftId)
        local vehicle = lift.kind == "twopost" and GetLiftTravelNow(lift) <= 0.001 and findCarBetween(lift)

        if (vehicle and getLiftFor(vehicle) == liftId and not IsPlayerBusy(vehicle)) then
            for across = -1, 1, 2 do
                add({
                    id = ("arms:%d:%d"):format(liftId, across),
                    coords = GetLiftWorld(lift, vec3(across * TwoPost.getPivot(1).x, 0.0, pointHeight)),
                    reach = armsReach,
                    label = T("target:setLiftArms"),
                    ---@return boolean canInteract
                    canInteract = function()
                        return DoesEntityExist(vehicle) and getLiftFor(vehicle) == liftId and not IsPlayerBusy(vehicle)
                    end,
                    onSelect = function()
                        setArms(vehicle)
                    end,
                })
            end
        end
    end
end)

CreateThread(function()
    -- zyke_lib picks the target system while it loads
    while (not HasLoaderFinished) do Wait(100) end

    if (UsesLiftInterestPoints()) then return end

    Z.target.addGlobalVehicle({
        distance = armsReach,
        options = {
            {
                name = "zyke_vehiclelifts:setArms",
                icon = "fas fa-up-down-left-right",
                label = T("target:setLiftArms"),
                ---@param entity integer
                ---@return boolean canInteract
                canInteract = function(entity)
                    return getLiftFor(entity) ~= nil and not IsPlayerBusy(entity)
                end,
                ---@param data {entity: integer} | integer @ ox_target passes the option data, qb-target the entity
                onSelect = function(data)
                    setArms(type(data) == "table" and data.entity or data)
                end,
            },
        },
    })
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName or not IsLiftSceneOpen()) then return end

    ClearPedTasks(PlayerPedId())
end)