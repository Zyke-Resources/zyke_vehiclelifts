-- zyke_lib interest points on every lift near the player, in place of the target menu unless
-- Config.Settings.vehiclelifts.interaction is "target". Each module adds the points it offers on every
-- pass, the one the crosshair is on shows its key and the key runs it. Nothing here runs while no lift
-- stands
local markerSet = "lift"
local interactKey = "zyke_vehiclelifts_interact"
-- Metres from the player a point is marked; its key only shows within the point's own reach
local markerDistance = 6.0
local refreshInterval = 250
local idleInterval = 1000

---@type (fun(add: fun(point: LiftInteractionPoint), pedCoords: vector3))[]
local collectors = {}
---@type table<string, LiftInteractionPoint> @ The points marked on the last pass, by id
local points = {}
---@type InterestPoint[]
local markers = {}
local pedCoords = vec3(0.0, 0.0, 0.0)
---@type boolean? @ Nil until it is asked for, once zyke_lib has picked the target system
local usesPoints
-- zyke_lib holds markers for the set right now
local markersShown = false
local interacting = false
local running = false

-- Collectors run on every pass and add the points that can be used near the player right now
---@param collect fun(add: fun(point: LiftInteractionPoint), pedCoords: vector3)
function RegisterLiftInteractionPoints(collect)
    collectors[#collectors + 1] = collect
end

---@param point LiftInteractionPoint
local function addPoint(point)
    if (#(point.coords - pedCoords) > math.max(markerDistance, point.reach)) then return end

    points[point.id] = point
    markers[#markers + 1] = {id = point.id, coords = point.coords, key = "+" .. interactKey, label = point.label, reach = point.reach}
end

---@return boolean offered
local function canOfferInteract()
    if (interacting or IsWorkingLift() or IsNuiFocused()) then return false end

    local ped = PlayerPedId()

    return not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false)
end

-- zyke_lib is another resource, so the set only goes over while it marks something and is cleared once
-- when it no longer does
local function setMarkers()
    if (#markers > 0) then
        markersShown = true

        Z.setInterestPoints(markerSet, markers, {aim = true})
    elseif (markersShown) then
        markersShown = false

        Z.clearInterestPoints(markerSet)
    end
end

---@return boolean nearby @ A point is marked, so the next pass comes at the full rate
local function refreshMarkers()
    points = {}
    markers = {}

    if (canOfferInteract()) then
        pedCoords = GetEntityCoords(PlayerPedId())

        for i = 1, #collectors do
            collectors[i](addPoint, pedCoords)
        end
    end

    setMarkers()

    return #markers > 0
end

local function interact()
    if (not canOfferInteract()) then return end

    local pointId = Z.getAimedInterestPoint(markerSet)
    local point = pointId and points[pointId]
    if (not point) then return end

    -- The point can stop applying between passes, such as the car rolling off
    if (not point.canInteract()) then
        Z.shakeInterestPoint(markerSet, pointId)

        return
    end

    interacting = true
    points = {}
    markers = {}

    setMarkers()

    -- Key callbacks come in from zyke_lib and the work yields until the player leaves it
    CreateThread(function()
        point.onSelect()

        interacting = false
    end)
end

-- Target is set by zyke_lib once its loader finishes, so this is only asked after HasLoaderFinished
---@return boolean usesInterestPoints @ False when the target menu offers the lifts instead
function UsesLiftInterestPoints()
    if (usesPoints ~= nil) then return usesPoints end

    local wantsTarget = Config.Settings.vehiclelifts.interaction == "target"

    usesPoints = not wantsTarget or not Target

    if (not usesPoints) then return false end
    if (wantsTarget) then print(("^3[%s] interaction is set to \"target\" but neither ox_target nor qb-target is started, using interaction points^7"):format(ResName)) end

    -- Only registered for interaction points, so target mode does not list a key that does nothing
    Z.registerKey(interactKey, "E", T("keybind:liftInteract"), interact)

    return true
end

-- Marks the points for as long as a lift stands
---@param isStanding fun(): boolean
function RunLiftInteractionPoints(isStanding)
    if (running) then return end

    running = true

    CreateThread(function()
        while (not HasLoaderFinished) do Wait(100) end

        if (UsesLiftInterestPoints()) then
            while (isStanding()) do
                Wait(refreshMarkers() and refreshInterval or idleInterval)
            end

            points = {}
            markers = {}

            setMarkers()
        end

        running = false
    end)
end

---@param resource string
AddEventHandler("onResourceStop", function(resource)
    if (resource == ResName and markersShown) then Z.clearInterestPoints(markerSet) end
end)