-- What other resources ask of the lifts: a rule that refuses to work a lift, the stop a lift holds a car
-- at, whether a car that is let down stays frozen, and a trim of a car's pose on the pads. Each goes
-- when the resource that set it stops. A rule lives in another resource, which can error or stop at
-- any time, so it is called guarded
---@type table<string, LiftRulesEntry>
local rules = {}
---@type table<NetId, table<string, LiftTrim>> @ The trims each resource set on a car, by its net id
local trims = {}
-- The most a car's pose may be trimmed by: degrees of pitch and metres of height
local mostPitch = 5.0
local mostHeight = 0.25

-- Functions crossing an export arrive as callable funcref tables
---@param value function | table
---@return boolean callable
local function isCallable(value)
    if (type(value) == "function") then return true end

    local mt = type(value) == "table" and getmetatable(value)

    return type(mt) == "table" and mt.__call ~= nil
end

---@param entry LiftRulesEntry
---@param key "canWork" | "lowestStop" | "holdFrozen"
---@param ... any
---@return boolean called @ False when the rule has no such function or it failed
---@return any first
---@return any second
local function call(entry, key, ...)
    local fn = entry[key]
    if (not fn) then return false end

    local ok, first, second = pcall(fn, ...)
    if (not ok) then Z.debug("Lift rule failed", entry.resource, entry.name, key, first) return false end

    return true, first, second
end

-- The first rule that refuses the work, by its own text
---@param data LiftWorkData
---@return string? text
function GetLiftRefusal(data)
    for _, entry in pairs(rules) do
        local called, allowed, text = call(entry, "canWork", data)
        if (called and allowed == false) then return type(text) == "string" and text or T("actionUnavailable") end
    end

    return nil
end

-- The highest of the stops the rules hold a car at, so it comes down no lower
---@param vehicle integer
---@param stops LiftStop[]
---@return number? travel
---@return string? text @ The rule's own, for a player who asks it to come down further
function GetLiftHold(vehicle, stops)
    local held, heldText

    for _, entry in pairs(rules) do
        local called, name, text = call(entry, "lowestStop", vehicle)

        if (called and name) then
            for _, stop in ipairs(stops) do
                if (stop.name == name and (not held or stop.travel > held)) then held, heldText = stop.travel, type(text) == "string" and text or nil end
            end
        end
    end

    return held, heldText
end

---@param vehicle integer
---@return boolean held @ A rule keeps the car frozen once it is let down
function IsLiftCarHeld(vehicle)
    for _, entry in pairs(rules) do
        local called, held = call(entry, "holdFrozen", vehicle)
        if (called and held == true) then return true end
    end

    return false
end

---@param netId NetId
---@return LiftTrim? trim @ What every resource's trim of the car comes to, nil for none
function GetLiftTrim(netId)
    local set = trims[netId]
    if (not set) then return nil end

    local pitch, height = 0.0, 0.0

    for _, trim in pairs(set) do
        pitch += trim.pitch
        height += trim.height
    end

    return {pitch = math.max(-mostPitch, math.min(mostPitch, pitch)), height = math.max(-mostHeight, math.min(mostHeight, height))}
end

-- Registering again under the same name replaces the earlier rules
---@param name string @ Unique within the registering resource
---@param set LiftRules
---@return boolean registered
exports("RegisterLiftRules", function(name, set)
    if (type(name) ~= "string" or name == "" or type(set) ~= "table") then return false end

    for _, key in ipairs({"canWork", "lowestStop", "holdFrozen"}) do
        if (set[key] ~= nil and not isCallable(set[key])) then return false end
    end

    local resource = GetInvokingResource() or ResName
    rules[resource .. ":" .. name] = {
        resource = resource,
        name = name,
        canWork = set.canWork,
        lowestStop = set.lowestStop,
        holdFrozen = set.holdFrozen,
    }

    return true
end)

---@param name string
---@return boolean removed
exports("RemoveLiftRules", function(name)
    local key = (GetInvokingResource() or ResName) .. ":" .. tostring(name)
    if (not rules[key]) then return false end

    rules[key] = nil

    return true
end)

-- The calling resource's trim of a car's pose on the pads, added to every other resource's. It stays
-- with the car while it is let down and taken up again, until it is set to nil or the resource stops
---@param vehicle integer
---@param trim? LiftTrim
---@return boolean set
exports("SetVehicleLiftTrim", function(vehicle, trim)
    if (type(vehicle) ~= "number" or not DoesEntityExist(vehicle)) then return false end
    if (trim ~= nil and (type(trim) ~= "table" or type(trim.pitch) ~= "number" or type(trim.height) ~= "number" or trim.pitch ~= trim.pitch or trim.height ~= trim.height)) then return false end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local set = trims[netId] or {}

    set[GetInvokingResource() or ResName] = trim and {pitch = trim.pitch, height = trim.height} or nil
    trims[netId] = next(set) and set or nil

    RefreshLiftTrim(vehicle)

    return true
end)

---@param entity integer
AddEventHandler("entityRemoved", function(entity)
    if (GetEntityType(entity) ~= 2) then return end

    trims[NetworkGetNetworkIdFromEntity(entity)] = nil
end)

-- A stopped resource's function references can no longer be called, and its trims go with it
---@param resource string
AddEventHandler("onResourceStop", function(resource)
    for key, entry in pairs(rules) do
        if (entry.resource == resource) then rules[key] = nil end
    end

    for netId, set in pairs(trims) do
        if (set[resource]) then
            set[resource] = nil
            trims[netId] = next(set) and set or nil

            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if (vehicle ~= 0 and DoesEntityExist(vehicle)) then RefreshLiftTrim(vehicle) end
        end
    end
end)