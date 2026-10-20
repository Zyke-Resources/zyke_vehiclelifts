# [> Download](https://github.com/Zyke-Resources/zyke_vehiclelifts/releases/latest)

# Zyke Vehicle Lifts

Two-post car lifts with a power unit worked by hand and arms set under the car's jacking points. Free, and built for other resources to place lifts of their own.

This resource manages the following:

- A two-post lift with four arms, a power unit and a lock release on the posts.
- Three stops on the way up: low for work on a creeper, waist for wheels and high to walk under, or straight to the top or the bottom with one key.
- Server-synced motion, so every player sees the carriages and the car at the same height.
- Lifts from a config file, an in-game placing tool that saves them in the database, or another resource's export.
- Rules other resources can put on every lift, such as holding a car up while a wheel is off.
- Lifts and the cars on them that survive a restart.
- Synced sounds through `zyke_sounds`: the pump going up, the oil flowing back coming down, the lock release, a pawl clicking over each notch and a clunk as the carriages settle.
- No idle cost: props stream in within 90 m, and nothing runs every frame while a lift stands still.

## Showcase

- [Video Link](https://youtu.be/ne1GsOWtQzw)

## Installation

1. Install `zyke_lib` and `oxmysql`, then place this resource in your server's resources folder as `zyke_vehiclelifts`.
2. Start it after `zyke_lib` and `oxmysql`, and before any resource that uses it:

```cfg
ensure oxmysql
ensure zyke_lib
ensure zyke_vehiclelifts
```

3. For sound, install [zyke_sounds](https://github.com/ZykeWasTaken/zyke_sounds), copy `extras/sounds/vehiclelifts` into `zyke_sounds/nui/sounds` and restart `zyke_sounds`. Without it the lifts work silently.
4. Run `/vehiclelifts` in game and place your lifts. They are saved in the `zyke_vehiclelifts` table, which is made the first time the resource starts, so there is no SQL to import.

## Usage

- **Placing:** admins run `/vehiclelifts` to take out the placing tool. A see-through lift stands on the floor where you aim, with an arrow the way a car is driven in, and left mouse places it and saves it in the database, so it stands again after a restart. Lined up, the default, it keeps to the line across or along the nearest lift, turned the same way, and moves along it in 5 cm steps, so a row of lifts stands square; the panel shows how far it is from that lift. `C` switches to free placing and back. Free, the scroll wheel turns it 1° at a time, or 10° with `Shift` held. The tool stays out for the next lift until right mouse or `Esc` puts it away.
- **Removing:** with the tool out, `Z` switches it to removing. The lift you aim at is marked on the floor, and left mouse takes it away and deletes it from the database. `Z` again goes back to placing. Only lifts placed with the tool can be removed this way, since those from `shared/lifts.lua` or another resource are made again when they start.
- **Room:** a lift can't stand in another one: the copy turns red where its floor would cross another lift's, and the server refuses it. A lift needs 3.7 m of room across and 3.2 m of headroom, plus room for a car's roof over its sills at 2.2 m when it is up at high.
- **Setting the arms:** drive the car between the posts with the lift all the way down, aim at the marker on either carriage and press `E` for **Set Lift Arms**. Hold left mouse on a pad and drag it with the cursor to the ring under its jacking point; it drops into place once it is near and comes off again when pulled well away. On a small car whose sills stand too near the arms' pivots, a pad sits up to 15 cm in under the car from the edge of the sill. `A` and `D` change corner and `Esc` leaves.
- **Snapping the car square:** a car parked a little off centre or a little crooked is moved to stand square in the middle of the lift as the arms are opened, so all four pads sit evenly under it. `snap` in `shared/config.lua` sets how far off it may be: `distance` in metres from the lift's middle and `angle` in degrees off straight. Set both to `0` to leave every car where it was parked.
- **Raising and lowering:** aim at the marker on the power unit on the right post and press `E` for **Work the Lift**. `E` is the default for both markers and can be changed in the game's key bindings under FiveM. Hold `E` to raise and `Q` to lower; the carriages stop at each height by themselves. `W` sends them all the way up and `S` all the way down without holding a key, and `Space` stops them. `Esc` leaves, and carriages sent all the way keep going.

With `interaction = "target"` both are options in the target menu instead, on the car and on the power unit.

A lift only goes up with all four pads under the car, or empty with every arm parked against its post.

## Configuration

- `shared/config.lua`: each kind's carriage speed and stop heights, `snap`, `sounds`, the admin command and who may use it (`admin.permission`, an ACE or an ESX group) and `interaction`, which picks between interaction points (`"point"`, the default) and ox_target or qb-target (`"target"`), under `Config.Settings.vehiclelifts`.
- `shared/lifts.lua`: the lifts that always stand.
- `client/can_checks.lua` and `server/can_checks.lua`: `CanWorkLift` decides who may set the arms (`arms`), raise (`up`) and lower (`down`).
- `server/hooks.lua`: `OnLiftMoved` runs whenever a player moves a lift.

## Developer integration

### Placing a lift

```lua
-- Server
local function placeLifts()
    exports["zyke_vehiclelifts"]:CreateLift({
        coords = vector3(-1366.5, -3007.1, 12.95), -- on the floor, midway between the posts
        heading = 240.0, -- the way a car's nose points when it is driven in
        kind = "twopost", -- optional: the kind of lift, "twopost" when left out
        bucket = 7301, -- optional: the routing bucket it stands in
    })
end

-- zyke_vehiclelifts forgets your lifts when it restarts
AddEventHandler("onResourceStart", function(resource)
    if (resource == "zyke_vehiclelifts") then placeLifts() end
end)

if (GetResourceState("zyke_vehiclelifts") == "started") then placeLifts() end
```

`CreateLift` returns the lift's id, and calling it again for the same spot and bucket returns the same lift. A lift with a `bucket` is only seen and worked from that routing bucket, so instanced interiors can each have their own at the same coords. Without one it stands in every bucket. A lift goes when the resource that made it calls `RemoveLift(liftId)` or stops; the car on it is set down on its wheels. A resource that restarts within 15 s and places the lift again keeps the car up.

Rules, trims and busy checks are dropped when `zyke_vehiclelifts` restarts, so register them the same way.

### Rules on every lift

```lua
-- Server. Every function is optional, and text you return is shown to the player as it is
exports["zyke_vehiclelifts"]:RegisterLiftRules("myJob", {
    -- data.action is "arms", "up" or "down", and data.vehicle the car on the pads, if any
    canWork = function(data)
        if (data.vehicle and IsMyJobRunning(data.vehicle)) then return false, T("myJobRunning") end

        return true
    end,
    -- Hold the car no lower than "low", "waist" or "high"
    lowestStop = function(vehicle)
        if (IsWheelMissing(vehicle)) then return "low", T("wheelMissing") end
    end,
    -- Keep the car frozen once it is back on its wheels
    holdFrozen = function(vehicle)
        return IsMyJobHoldingIt(vehicle)
    end,
})
```

### Tilting the car

```lua
-- Server. Pitch in degrees, nose up, and height in metres, at most 5 degrees and 0.25 m. nil clears it
exports["zyke_vehiclelifts"]:SetVehicleLiftTrim(vehicle, {pitch = 1.2, height = 0.02})
```

### Keeping the player off the lifts

```lua
-- Client. While it returns true, the power unit and the arms are not offered
exports["zyke_vehiclelifts"]:RegisterBusyCheck("myJob", function(vehicle)
    return IsMyMenuOpen()
end)
```

## Events

| Server event | When it fires |
| --- | --- |
| `zyke_vehiclelifts:OnLiftMoved` | A player sends a lift up or down (`source`, `liftId`, `from`, `goal`, `netId?`, `plate?`) |
| `zyke_vehiclelifts:OnVehicleLifted` | The pads take a car off the ground (`source`, `liftId`, `netId`, `plate`) |
| `zyke_vehiclelifts:OnVehicleLowered` | A car is back on its wheels and let go of (`liftId`, `netId`, `plate`) |

These events are notifications only and can not block an action; use `RegisterLiftRules` for that.

## Exports

### Server

- `CreateLift({coords, heading?, kind?, bucket?})`: the lift's id, nil for options that stand no lift
- `RemoveLift(liftId)`: takes away a lift the calling resource made, and returns whether it did
- `GetLift(liftId)`, `GetLifts()`
- `GetVehicleLift(vehicle)`: the car's lift record, nil for a car on no lift
- `IsVehicleOnLift(vehicle)`, `IsVehicleOnMovingLift(vehicle)`
- `GetVehicleLiftStop(vehicle)`: `"low"`, `"waist"`, `"high"` or nil, and whether the lift is moving
- `RegisterLiftRules(name, rules)`, `RemoveLiftRules(name)`
- `SetVehicleLiftTrim(vehicle, trim?)`

### Client

- `GetLift(liftId)`
- `GetLiftTravel(liftId)`: metres the carriages stand up, and whether they are moving
- `GetLiftUnder(vehicle)`: the lift the car stands between the posts of, the one whose middle is nearest where two stand in each other
- `IsWorkingLift()`: the player is at a power unit, setting arms or placing a lift
- `GetVehicleLift(vehicle)`, `IsVehicleOnLift(vehicle)`, `IsVehicleOnMovingLift(vehicle)`, `GetVehicleLiftStop(vehicle)`
- `RegisterBusyCheck(name, isBusy)`, `RemoveBusyCheck(name)`

The `zykeVehicleLift` state bag on a car and the `zykeVehicleLifts` global state are read-only.

## License

Free to use and modify on your own server, including servers that make money. See [LICENSE](LICENSE) for the full terms.

- **Open releases:** a project whose full source anyone can download for free from a public host such as GitHub, with no store checkout or free basket, may include this resource. Credit Zyke Resources, link to this repository and keep the license file with it.
- **Closed releases:** paid releases and free releases that are escrowed or otherwise locked may not ship any of it. Use it through its exports and tell your users to download it from here.
- **Videos and showcases:** anyone may show it, as long as Zyke Resources is named as the source.
- Selling it on its own, or claiming it as your own, is not allowed.

## Links

- [Discord Community](https://discord.zykeresources.com)
- [Store](https://store.zykeresources.com/)
