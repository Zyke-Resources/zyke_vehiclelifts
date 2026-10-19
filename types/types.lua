---@alias LiftKindName "twopost"
---@alias LiftAction "arms" | "up" | "down" @ Setting a lift's arms under a car, or sending its carriages up or down
---@alias LiftStopName "low" | "waist" | "high" @ The heights a car on a lift's pads stops at, see Config.Settings.vehiclelifts.kinds
---@alias LiftSceneResult "cancelled" | "interrupted" | "unavailable"
---@alias LiftSoundKey "motor" | "lower" | "release" | "pawl" | "clunk" @ See Config.Settings.vehiclelifts.sounds

---@class LiftOptions @ What CreateLift stands a lift from
---@field coords vector3 @ On the floor, midway between the posts
---@field heading? number @ Degrees, the way a car's nose points when it is driven on. 0 when left out
---@field kind? LiftKindName @ "twopost" when left out
---@field bucket? integer @ The routing bucket it stands in, seen and worked only from there. Every bucket when left out

---@class LiftArm @ Where an arm is set
---@field swing number @ Degrees from straight across the lift toward along its post
---@field reach number @ Metres from its pivot out to the middle of its pad
---@field seated? true @ Its pad sits under the jacking point of the car the arms were set under

---@class LiftMotion @ Where a lift's carriages set off from, toward what and when, on the server's game timer
---@field travel number @ Metres up from the bottom they set off from
---@field goal number @ Metres up from the bottom they stop at
---@field movedAt integer @ Milliseconds on the server's game timer they set off at
---@field speed number @ Metres a second

---@class ZykeVehicleLift: LiftMotion @ A lift in the zykeVehicleLifts global state, read-only
---@field id integer
---@field kind LiftKindName
---@field coords vector3
---@field heading number
---@field owner string @ The resource that made it, which takes it away as it stops
---@field arms LiftArm[]
---@field netId? NetId @ The car the arms were set under
---@field placed? true @ Placed with the admin command
---@field bucket? integer @ The routing bucket it stands in, nil for every bucket

---@class LiftStop
---@field name LiftStopName | "bottom" | "top"
---@field travel number @ Metres up from the bottom, on a lock

---@class LiftTrim @ How much a car's pose on a lift's pads is pitched and raised
---@field pitch number @ Degrees, the nose up
---@field height number @ Metres

---@class LiftCarTrim: LiftTrim @ A trim on a car's record, on its way from the one before it
---@field from? LiftTrim
---@field at? integer @ Milliseconds on the server's game timer it was set at

---@class LiftMeasure @ What a client reads off a car as it stands on its wheels
---@field coords vector3
---@field rotation vector3
---@field axles {front: number, rear: number} @ Metres along the car
---@field points {front: vector3, rear: vector3} @ Vehicle space, the jacking points on its right
---@field sill number @ Metres its lowest jacking point stands off the ground
---@field hub number @ Vehicle space height of its front hubs

---@class LiftCar @ A car up on a lift's pads, in its zykeVehicleLift state bag, read-only. A car without the bag is on no lift
---@field liftId integer
---@field kind LiftKindName
---@field coords vector3 @ Where it stood on its wheels
---@field rotation vector3
---@field points {front: vector3, rear: vector3}
---@field gap number @ Metres the carriages travel before the pads take it
---@field sill number @ Metres its lowest jacking point stood off the lift's floor
---@field hub number @ Metres its hubs stood off the lift's floor
---@field motion LiftMotion @ The lift's carriages, which it rises and comes down with
---@field trim? LiftCarTrim

---@class LiftKind @ What every kind of lift tells, see shared/twopost.lua
---@field arms integer
---@field lockStep number @ Metres between two locks
---@field travel number @ The most the carriages travel
---@field powerAt vector3 @ Lift frame, the power unit's button
---@field operatorAt vector2 @ Lift frame, where its user stands
---@field footprint vector2 @ Half the floor it stands on, across and along
---@field speed number @ Metres a second
---@field parked LiftArm
---@field clampArm fun(swing: number, reach: number): LiftArm
---@field isArmParked fun(pose: LiftArm): boolean
---@field isPadSeated fun(arm: integer, pose: LiftArm, corner: vector3): boolean
---@field getCorners fun(lift: {coords: vector3, heading: number}, measure: LiftMeasure | LiftCar): vector3[]?
---@field getCarHeights fun(lift: {coords: vector3, heading: number}, measure: LiftMeasure, corners: vector3[]): number, number, number
---@field getStops fun(car?: {gap: number, sill: number, hub: number}): LiftStop[]
---@field lockAt fun(travel: number): vector3 @ Lift frame, where the locks catch the carriages at that height

---@class LiftRules @ What a resource asks of the lifts through RegisterLiftRules
---@field canWork? fun(data: LiftWorkData): boolean?, string? @ False and its own text refuse the work
---@field lowestStop? fun(vehicle: integer): LiftStopName?, string? @ The stop the car comes down no lower than, and its own text for a player who asks it to
---@field holdFrozen? fun(vehicle: integer): boolean @ True keeps the car frozen once it is let down

---@class LiftRulesEntry: LiftRules
---@field resource string
---@field name string

---@class LiftWorkData
---@field source PlayerId
---@field liftId integer
---@field kind LiftKindName
---@field owner string
---@field action LiftAction
---@field vehicle? integer @ The car the work is about
---@field netId? NetId
---@field lifted boolean @ The car is up on the pads already

---@class LiftHookData
---@field source PlayerId
---@field liftId integer
---@field kind LiftKindName
---@field owner string
---@field coords vector3
---@field from number @ Metres up from the bottom
---@field goal number
---@field netId? NetId @ The car on the pads
---@field modelHash? integer
---@field plate? string

---@class LiftCarHookData
---@field source? PlayerId @ The player at the power unit as the car is taken up
---@field liftId integer
---@field netId NetId
---@field modelHash integer
---@field plate string

---@class LiftSound
---@field name string @ Path inside zyke_sounds/nui/sounds
---@field volume number @ 0.0 to 1.0
---@field distance number @ Metres it is heard from

---@class LiftSounds @ The sounds of a lift's motion that are playing, see server/sounds.lua
---@field count integer @ Counts its motions, so the timers of an older one leave a newer one be
---@field running? "motor" | "lower" @ The loop that plays while the carriages travel
---@field id? string @ The zyke_sounds id of that loop

---@class LiftCarSet @ The car a lift's arms were set under
---@field netId NetId
---@field vehicle integer
---@field measure LiftMeasure
---@field corners vector3[] @ Lift frame, the jacking point under each arm
---@field gap number
---@field sill number
---@field hub number

---@class LiftLever
---@field plyId PlayerId
---@field id string

---@class LiftArmSession
---@field id string
---@field liftId integer

---@class LiftKept @ A lift that went with its maker or a restart, until it is made again
---@field lift ZykeVehicleLift
---@field expiresAt integer @ Game timer a car still on it is set down at

---@class LiftBusyEntry
---@field resource string
---@field name string
---@field isBusy fun(vehicle?: integer): boolean

---@class LiftInteractionPoint @ A spot on a lift the player uses with the interact key, see client/interactions.lua
---@field id string @ Stable between passes
---@field coords vector3 @ World
---@field reach number @ Metres from the player it can be used from
---@field label string
---@field canInteract fun(): boolean @ Asked again as the key is pressed
---@field onSelect fun()

---@class LiftSet @ A kind of lift's props, see client/twopost_set.lua
---@field models table<string, string>
---@field solid table<string, true>
---@field pads fun(lift: ZykeVehicleLift, car: LiftCar, now?: integer): LiftPads?
---@field pieces fun(travel: number, arms: LiftArm[], pads?: LiftPads, lowering: boolean): LiftPiece[]
---@field isBetween fun(point: vector3): boolean

---@class LiftPads @ The car on a lift's pads, as the pads are drawn
---@field yaw number @ Degrees the car is turned from the lift, which the pads' slots follow
---@field winds number[] @ Metres each pad is wound up to meet its sill
---@field moving boolean @ The carriages travel or the car eases to a trim

---@class LiftPiece @ One prop of a lift and where it stands
---@field key string @ Which of the lift's props it is, as "arm3"
---@field model string
---@field at vector3 @ Lift frame, its origin
---@field yaw number @ Degrees it is turned from the lift
---@field pitch? number @ Degrees it is turned about its own X
---@field roll? number @ Degrees it is turned about its own Y

---@class ShownLift @ A lift this client stands props for
---@field entities table<string, integer> @ By the key of each piece
---@field following boolean @ It is drawn every frame while its carriages travel
---@field travel? number @ How high the carriages were last drawn

---@class LiftTrackedCar @ A car on a lift as this client poses it
---@field easing boolean @ Its carriages travel or its trim eases, and its pose is followed every frame
---@field car? LiftCar
---@field vehicle? integer

---@class LiftView
---@field at vector3 @ Frame space
---@field target vector3

---@class LiftPowerSession @ The player at a lift's power unit
---@field liftId integer
---@field sessionId string
---@field pressed 1 | -1 | 0 @ The key held: E to raise, Q to lower
---@field heldOver boolean @ A key held since before the player took the power unit, not counted until let go
---@field sending 1 | -1 | 0 @ The way this player sent the carriages all the way, 0 once they no longer go by themselves
---@field sentAt integer @ Game timer they were sent at
---@field halting? boolean @ The keys show the one that stops them
---@field keybinds? LiftKeybindItem[]
---@field done boolean

---@class LiftSceneState
---@field ped integer
---@field origin vector3
---@field axisX vector3
---@field axisY vector3
---@field axisZ vector3
---@field view LiftView
---@field fov number
---@field moved boolean
---@field cam? integer
---@field hideAt? integer
---@field keybinds? LiftKeybindItem[] @ The keys shown over it, hidden as it closes

---@class LiftSceneSession
---@field scene? LiftSceneState

---@class LiftArmsGame
---@field liftId integer
---@field lift ZykeVehicleLift
---@field sessionId string
---@field corners vector3[] @ Lift frame, the car's jacking point under each arm
---@field marks table<integer, vector3> @ World, where the ring under each arm's jacking point is drawn
---@field arms LiftArm[] @ As this scene has them
---@field arm integer @ The corner the view is at
---@field holding boolean @ The hand has the pad
---@field keybinds? LiftKeybindItem[]
---@field scene? LiftSceneState
---@field ready? boolean @ The view has arrived
---@field result? LiftSceneResult
---@field goal? vector2 @ Lift frame, where the hand has the pad go
---@field outOfPark? boolean @ The held pad has been out of its park, so it may drop back in
---@field context? string