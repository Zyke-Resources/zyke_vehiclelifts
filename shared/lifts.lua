-- The lifts that stand in the world for as long as this resource runs. Each stands its props for every
-- player near it. Lifts placed in game with "/vehiclelifts" are saved in the database instead, see
-- server/database.lua. Each line here takes:
--   coords   On the floor, midway between where the two posts stand
--   heading  Degrees, the way a car's nose points when it is driven in between the posts
--   kind     Which lift it is, see Config.Settings.vehiclelifts.kinds. "twopost" when left out
-- A two-post lift's right post, with the power unit on its outside, stands 1.6 m to the right of that
-- way. The posts want 3.7 m of room across and 3.2 m of headroom, and a car wants its length of room along
-- and its roof's height over 2.2 m of headroom at high.
-- Other resources stand lifts of their own through the CreateLift export, see README.md
---@type {coords: vector3, heading: number, kind?: LiftKindName}[]
VehicleLifts = {
}