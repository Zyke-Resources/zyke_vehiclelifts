-- The view of a lift's arms being set: a frame fixed to the lift's floor plate, the camera that eases in
-- from the player's own view, and the cursor's line of sight into that frame. The frame's X, Y and Z are
-- the lift's own, see shared/lift.lua. One scene is open at a time
LiftScene = {}

-- Milliseconds the view takes to travel between the player's own camera and the one at the arm
local easeTime = 900
local nearClip = 0.02
-- The player can stand in the way of the camera, so they are hidden for the last of the way in and the first of the way out
local hideAfter = 450
local hideOnExit = 500
local torchColour = {255, 244, 229}
-- Frame space offset of the torch from the camera, off to one side so the arm gets a lit and a shaded side
local torchOffset = vec3(0.16, 0.0, 0.10)
-- Reach, brightness, roundness, cone angle and falloff of the beam
local torchBeam = {2.5, 2.2, 0.0, 46.0, 6.0}

---@param a vector3
---@param b vector3
---@return vector3 product
local function cross(a, b)
    return vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

---@param a vector3
---@param b vector3
---@return number product
local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

---@param vector vector3
---@param fallback vector3 @ Returned for a vector too short to have a direction
---@return vector3 unit
local function unit(vector, fallback)
    local length = #vector
    if (length < 0.000001) then return fallback end

    return vector / length
end

---@param entity integer @ The floor plate, standing at the lift's origin and turned its way
---@param ped integer
---@param view LiftView @ Where the camera starts
---@param fov number @ Degrees
---@return LiftSceneState scene
function LiftScene.create(entity, ped, view, fov)
    local forward, right, up, at = GetEntityMatrix(entity)

    ---@type LiftSceneState
    return {
        ped = ped,
        origin = at,
        axisX = right,
        axisY = forward,
        axisZ = up,
        view = {at = view.at, target = view.target},
        fov = fov,
        moved = true,
    }
end

---@param scene LiftSceneState
---@param offset vector3 @ Frame space
---@return vector3 position
function LiftScene.toWorld(scene, offset)
    return scene.origin + scene.axisX * offset.x + scene.axisY * offset.y + scene.axisZ * offset.z
end

---@param scene LiftSceneState
local function aimCamera(scene)
    local at = LiftScene.toWorld(scene, scene.view.at)
    local forward = unit(LiftScene.toWorld(scene, scene.view.target) - at, scene.axisY)

    SetCamCoord(scene.cam, at.x, at.y, at.z)
    SetCamFov(scene.cam, scene.fov)
    SetCamRot(scene.cam, math.deg(math.asin(math.max(-1.0, math.min(1.0, forward.z)))), 0.0, math.deg(math.atan(-forward.x, forward.y)), 2)
end

-- The view travels in from wherever the player's own camera is, there is no cut
---@param scene LiftSceneState
function LiftScene.openCamera(scene)
    scene.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    SetCamNearClip(scene.cam, nearClip)
    aimCamera(scene)
    RenderScriptCams(true, true, easeTime, true, true)

    scene.hideAt = GetGameTimer() + hideAfter
end

---@return integer duration @ Milliseconds the camera takes to arrive
function LiftScene.easeTime()
    return easeTime
end

-- The torch the player works by, held beside the head and pointed at the arm
---@param scene LiftSceneState
local function torch(scene)
    local at = LiftScene.toWorld(scene, scene.view.at + torchOffset)
    local direction = unit(LiftScene.toWorld(scene, scene.view.target) - at, scene.axisY)

    DrawSpotLightWithShadow(at.x, at.y, at.z, direction.x, direction.y, direction.z, torchColour[1], torchColour[2], torchColour[3], torchBeam[1], torchBeam[2], torchBeam[3], torchBeam[4], torchBeam[5], 0)
end

-- One frame of an open scene: the game's controls stay off apart from push to talk, and the view moves
-- on toward where it is wanted
---@param scene LiftSceneState
---@param view LiftView
---@param dt number
function LiftScene.tick(scene, view, dt)
    local current = scene.view
    local blend = 1.0 - math.exp(-dt * 7.0)

    DisableAllControlActions(0)
    EnableControlAction(0, 249, true)
    HideHudAndRadarThisFrame()

    if (#(view.at - current.at) > 0.0004 or #(view.target - current.target) > 0.0004) then
        current.at = current.at + (view.at - current.at) * blend
        current.target = current.target + (view.target - current.target) * blend
        scene.moved = true
    end

    if (scene.moved) then aimCamera(scene) end

    torch(scene)

    if (scene.hideAt and GetGameTimer() >= scene.hideAt) then SetEntityLocallyInvisible(scene.ped) end

    scene.moved = false
end

---@return number cursorX @ Normalized screen position
---@return number cursorY @ Normalized screen position
function LiftScene.cursor()
    return GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
end

-- The cursor's line of sight from the camera
---@param scene LiftSceneState
---@param cursorX number @ Normalized screen position
---@param cursorY number @ Normalized screen position
---@return vector3 ray @ Frame space unit vector
function LiftScene.cursorRay(scene, cursorX, cursorY)
    local view = scene.view
    local forward = unit(view.target - view.at, vec3(0.0, 1.0, 0.0))
    local right = unit(cross(forward, vec3(0.0, 0.0, 1.0)), vec3(1.0, 0.0, 0.0))
    local up = cross(right, forward)
    local halfHeight = math.tan(math.rad(scene.fov) / 2.0)

    return unit(forward + right * ((cursorX * 2.0 - 1.0) * halfHeight * GetAspectRatio(false)) + up * ((1.0 - cursorY * 2.0) * halfHeight), forward)
end

-- Where the cursor's line of sight meets a plane
---@param scene LiftSceneState
---@param ray vector3 @ Frame space unit vector from LiftScene.cursorRay
---@param through vector3 @ Frame space point of the plane
---@param normal vector3 @ Frame space
---@return vector3? point @ Frame space, nil when the ray runs along the plane or away from it
function LiftScene.rayOnPlane(scene, ray, through, normal)
    local at = scene.view.at
    local facing = dot(ray, normal)
    if (math.abs(facing) < 0.0001) then return nil end

    local distance = dot(through - at, normal) / facing
    if (distance <= 0.0) then return nil end

    return at + ray * distance
end

-- Releasing ESC after the scene closes would otherwise open the pause menu
function LiftScene.holdPauseMenu()
    CreateThread(function()
        local heldUntil = GetGameTimer() + 500
        while (GetGameTimer() < heldUntil or IsDisabledControlPressed(0, 200) or IsDisabledControlPressed(0, 202)) do
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 202, true)

            if (IsPauseMenuActive()) then SetFrontendActive(false) end

            Wait(0)
        end
    end)
end

---@type LiftSceneSession?
local open

-- Hands the view back and shows the player again once the camera is out
local function close()
    local session = open
    if (not session) then return end

    open = nil

    local scene = session.scene
    if (scene and scene.keybinds) then LiftKeybinds.hide(scene.keybinds) end

    if (scene and scene.cam) then
        local ped = scene.ped
        local shownAt = GetGameTimer() + hideOnExit

        RenderScriptCams(false, true, easeTime, true, false)
        DestroyCam(scene.cam, false)

        CreateThread(function()
            while (GetGameTimer() < shownAt) do
                SetEntityLocallyInvisible(ped)

                Wait(0)
            end
        end)
    end

    LiftScene.holdPauseMenu()
end

---@return boolean open
function IsLiftSceneOpen()
    return open ~= nil
end

-- Runs a scene, one at a time. A failure part way through must not leave the player with the controls locked
---@param play fun(session: LiftSceneSession, ...): LiftSceneResult @ Builds the scene and runs it until the player is done
---@param ... any @ Handed on to play after the session
---@return LiftSceneResult result
function LiftScene.run(play, ...)
    if (open) then return "unavailable" end

    open = {}
    local completed, result = xpcall(play, debug.traceback, open, ...)

    close()

    if (not completed) then
        print(("^1[ERROR] [%s] %s^7"):format(ResName, result))

        return "unavailable"
    end

    return result
end

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource ~= ResName) then return end

    close()
end)