-- A lift's sounds through zyke_sounds while it is started: the pump while the carriages go up, the oil
-- flowing back while the lowering handle lets them down, a pawl clicking over each notch on the way up and
-- a clunk as they come to rest. They are played at the lift for every player near it, and each motion
-- of a lift takes over from the one before it
local settings = Config.Settings.vehiclelifts.sounds
-- Milliseconds a loop fades out over as the carriages arrive, and over which one that is replaced is cut
local fadeMs = 300
local cutMs = 80

---@type table<integer, LiftSounds> @ By lift
local playing = {}

---@return boolean started
local function isStarted()
    return settings.enabled == true and Z.isResourceStarted("zyke_sounds")
end

---@param lift ZykeVehicleLift
---@param key LiftSoundKey
---@param at vector3 @ Lift frame
---@param id? string @ Given for a loop, to stop it by
local function play(lift, key, at, id)
    local sound = settings[key]
    if (type(sound) ~= "table" or not isStarted()) then return end

    exports["zyke_sounds"]:PlaySoundOnLocation({
        location = GetLiftWorld(lift, at),
        id = id,
        soundName = sound.name,
        maxVolume = sound.volume,
        maxDistance = sound.distance,
        looped = id ~= nil,
        routingBucket = lift.bucket,
        global = lift.bucket == nil,
        -- Each client registers the lift's props and the vehicles around it, see client/sound_occlusion.lua
        occlusionIgnore = "zyke_vehiclelifts",
    })
end

---@param state LiftSounds
---@param fade integer @ ms
local function stopLoop(state, fade)
    if (state.id and isStarted()) then exports["zyke_sounds"]:StopSound(state.id, fade) end

    state.running, state.id = nil, nil
end

-- Plays the motion a lift's carriages just set off on, from lift.travel toward lift.goal. Carriages that
-- go on the same way keep the loop they had
---@param lift ZykeVehicleLift
---@param lowering? boolean @ The lowering handle lets them down, rather than the lock below catching them
function PlayLiftMotion(lift, lowering)
    local state = playing[lift.id] or {count = 0}
    local span = lift.goal - lift.travel
    local running = span > 0.001 and "motor" or (span < -0.001 and lowering and "lower") or nil
    local kind = LiftKinds[lift.kind]

    state.count += 1
    playing[lift.id] = state

    local count, goal = state.count, lift.goal

    if (state.running ~= running) then
        stopLoop(state, cutMs)

        if (running == "lower") then play(lift, "release", kind.powerAt) end

        if (running) then
            state.running, state.id = running, ("zyke_vehiclelifts:%d:%d"):format(lift.id, count)

            play(lift, running, kind.powerAt, state.id)
        end
    end

    if (math.abs(span) <= 0.001) then return end

    -- The pawl drops over each notch it passes on the way up, before the one the carriages stop on
    if (span > 0.0) then
        local notch = math.floor(lift.travel / kind.lockStep + 0.0001) + 1

        while (notch * kind.lockStep < goal - 0.001) do
            local at = notch * kind.lockStep

            SetTimeout(math.floor((at - lift.travel) / lift.speed * 1000.0), function()
                if (playing[lift.id] == state and state.count == count) then play(lift, "pawl", kind.lockAt(at)) end
            end)

            notch += 1
        end
    end

    local ms = GetLiftMotionMs(lift)

    SetTimeout(math.max(0, ms - fadeMs), function()
        if (playing[lift.id] ~= state or state.count ~= count) then return end

        stopLoop(state, fadeMs)

        Wait(math.min(ms, fadeMs))

        if (playing[lift.id] == state and state.count == count) then play(lift, "clunk", kind.lockAt(goal)) end
    end)
end

-- A lift taken out of the world goes quiet
---@param liftId integer
function StopLiftSounds(liftId)
    local state = playing[liftId]
    if (not state) then return end

    playing[liftId] = nil

    stopLoop(state, cutMs)
end