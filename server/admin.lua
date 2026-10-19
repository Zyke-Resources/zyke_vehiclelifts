-- Admin command: "/vehiclelifts" takes out the placing tool, see client/admin.lua, which places lifts
-- where the admin aims and takes away those it placed. A placed lift is saved in the database, see
-- server/database.lua
local admin = Config.Settings.vehiclelifts.admin
if (not admin or admin.enabled ~= true) then return end

-- Metres from the admin a lift they place or take away may stand. The placing tool reaches 12, and the
-- admin may walk on while the server is asked
local placeReach = 15.0

---@return string names @ Every kind of lift, in a fixed order
local function listKinds()
    local names = {}

    for name in pairs(LiftKinds) do
        names[#names + 1] = name
    end

    table.sort(names)

    return table.concat(names, ", ")
end

---@param plyId PlayerId
---@param args string[]
Z.registerCommand(admin.command, function(plyId, args)
    if (plyId <= 0) then return end

    local kind = (args[1] or "twopost"):lower()
    if (not LiftKinds[kind]) then Z.notify(plyId, "unknownLiftKind", {args[1], listKinds()}) return end

    -- The server has no floor to read, so the admin's client finds it
    TriggerClientEvent("zyke_vehiclelifts:PlaceLift", plyId, kind)
end, T("command:vehiclelifts"), {{"kind", T("command:vehicleliftsKind")}}, {permission = admin.permission, errorMsg = "noPermission"})

-- A lift standing in another would leave a car between the posts of both, see GetLiftUnder
---@param placed {kind: LiftKindName, coords: vector3, heading: number}
---@return boolean overlapping
local function isOverlapping(placed)
    for _, lift in pairs(GetLifts()) do
        if (DoLiftsOverlap(lift, placed)) then return true end
    end

    return false
end

-- The admin's client found the floor they aim at and the way the lift is turned
---@param plyId PlayerId
---@param coords vector3
---@param heading number
---@param kind LiftKindName
---@return integer? liftId
---@return string? notification
Z.callback.register("zyke_vehiclelifts:AddLift", function(plyId, coords, heading, kind)
    if (not Z.hasPermission(plyId, admin.permission)) then return nil, "noPermission" end
    if (type(coords) ~= "vector3" or type(heading) ~= "number" or heading ~= heading or not LiftKinds[kind]) then return nil, "actionUnavailable" end

    local ped = GetPlayerPed(plyId)
    if (ped == 0 or #(GetEntityCoords(ped) - coords) > placeReach) then return nil, "actionUnavailable" end
    if (isOverlapping({kind = kind, coords = coords, heading = heading})) then return nil, "liftOverlaps" end

    local liftId = CreateLift({coords = coords, heading = heading, kind = kind}, ResName, true)
    if (not liftId) then return nil, "actionUnavailable" end

    LiftDatabase.save(liftId, plyId)

    return liftId
end)

-- The placing tool takes away the lift the admin aims at, one placed with it
---@param plyId PlayerId
---@param liftId integer
---@return boolean removed
---@return string? notification
Z.callback.register("zyke_vehiclelifts:RemovePlacedLift", function(plyId, liftId)
    if (not Z.hasPermission(plyId, admin.permission)) then return false, "noPermission" end

    local lift = GetLifts()[liftId]
    if (not lift or not lift.placed) then return false, "actionUnavailable" end

    local ped = GetPlayerPed(plyId)
    if (ped == 0 or #(GetEntityCoords(ped) - lift.coords) > placeReach) then return false, "actionUnavailable" end

    local removed = RemoveLift(liftId)
    if (removed) then LiftDatabase.remove(liftId) end

    return removed
end)