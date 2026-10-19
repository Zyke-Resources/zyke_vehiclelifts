Config = Config or {}

Config.Settings = {
    vehiclelifts = {
        -- Every kind of lift, by the name CreateLift and shared/lifts.lua give it
        kinds = {
            -- A two-post lift. A car on its pads stops at three heights on its way up and down, each on the
            -- lock of the posts nearest to it
            twopost = {
                -- Metres a second the carriages travel at, up and down, for everyone in the bay at once
                speed = 0.10,
                -- Metres off the floor a car's sills stand at low, where it is worked lying on a creeper
                low = 0.55,
                -- Metres off the floor its wheel hubs stand at waist, where wheels and corners are worked standing
                waist = 0.95,
                -- Metres off the floor its sills stand at high, where it is walked under clear of the
                -- player's head and the camera. The posts take a car no higher than sills at 2.20
                high = 2.20,
            },
        },
        -- A car parked a little off when its arms are set is moved to stand square in the middle of the
        -- lift, so its pads sit evenly. It is moved when its jacking points stand no more than distance
        -- metres off the lift's middle and it is turned no more than angle degrees off straight. 0 for
        -- both leaves every car where it was parked
        snap = {
            distance = 0.30,
            angle = 8.0,
        },
        -- How the power unit and the arms are used: "point" marks them in the world to aim at and press
        -- E, "target" offers them through ox_target or qb-target instead and falls back to points
        -- without one
        interaction = "point",
        -- Sounds play through zyke_sounds while it is started, and the lifts are silent without it. Copy
        -- extras/sounds/vehiclelifts into zyke_sounds/nui/sounds and restart zyke_sounds. Names are paths
        -- inside zyke_sounds/nui/sounds; set a sound to false to mute it
        sounds = {
            enabled = true,
            -- The pump at the power unit, while the carriages go up
            motor = {name = "vehiclelifts/lift_motor.ogg", volume = 0.1, distance = 20.0},
            -- The oil flowing back, while the lowering handle lets them down
            lower = {name = "vehiclelifts/lift_lower.ogg", volume = 0.02, distance = 20.0},
            -- The locks released as the lowering handle is pulled
            release = {name = "vehiclelifts/lift_release.ogg", volume = 0.3, distance = 20.0},
            -- A lock's pawl clicking over each notch of the post on the way up
            pawl = {name = "vehiclelifts/lift_pawl.wav", volume = 0.6, distance = 20.0},
            -- The carriages settling onto a lock, or onto the floor
            clunk = {name = "vehiclelifts/lift_clunk.ogg", volume = 0.04, distance = 30.0},
        },
        -- "/vehiclelifts" takes out a tool that places two-post lifts where you aim, lined up with the
        -- lift nearest to it or free, and saves them in the database through oxmysql, so they stand
        -- again after a restart. The same tool takes away the lifts placed with it. Any one of the
        -- permissions allows it: an ACE, where "command" lets anyone with command access in, or on ESX
        -- a group name
        admin = {
            enabled = true,
            command = "vehiclelifts",
            permission = {"command", "admin", "superadmin", "owner"},
        },
    },
}