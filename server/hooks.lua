-- Editable reactions to lifts; other resources can listen to the zyke_vehiclelifts:OnLiftMoved,
-- zyke_vehiclelifts:OnVehicleLifted and zyke_vehiclelifts:OnVehicleLowered server events instead of
-- editing this file

-- Runs once a player has sent a lift's carriages up or down, as they set off from data.from toward
-- data.goal, both in metres up from the bottom. data.netId names the car on its pads, if there is
-- one: at the bottom it stands on its wheels, and it leaves the ground once the pads reach its sills
---@param data LiftHookData
function OnLiftMoved(data)
    -- Add dispatch exports or custom logic here
end