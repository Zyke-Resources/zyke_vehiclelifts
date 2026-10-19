-- The lift's sounds come from inside its posts and power unit, often with a car on the pads or parked
-- alongside between them and the player. zyke_sounds would muffle them behind those, so every lift this
-- client stands tells it which entities its sounds pass through, see server/sounds.lua
local key = "zyke_vehiclelifts"
-- Metres from a lift's middle a vehicle may stand and still let its sounds through
local vehicleReach = 15.0

---@type table<integer, integer[]> @ The entities each lift's sounds pass through, by lift
local ignored = {}

-- Hands zyke_sounds every lift's entities at once, as it keeps one list per key
local function push()
    if (not Z.isResourceStarted("zyke_sounds")) then return end

    local entities = {}

    for _, list in pairs(ignored) do
        for i = 1, #list do
            entities[#entities + 1] = list[i]
        end
    end

    exports["zyke_sounds"]:SetOcclusionIgnore(key, entities)
end

-- The lift's own props and every vehicle near it, read again each time it travels
---@param liftId integer
---@param coords vector3 @ World, the lift's middle
---@param props table<string, integer>
function SetLiftSoundIgnores(liftId, coords, props)
    local entities = {}

    for _, entity in pairs(props) do
        entities[#entities + 1] = entity
    end

    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        if (#(GetEntityCoords(vehicle) - coords) <= vehicleReach) then entities[#entities + 1] = vehicle end
    end

    ignored[liftId] = entities

    push()
end

---@param liftId integer
function ClearLiftSoundIgnores(liftId)
    if (not ignored[liftId]) then return end

    ignored[liftId] = nil

    push()
end