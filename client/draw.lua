-- See-through boxes drawn in the world, taken from zyke_chopshop's grid building: a tint on the floor
-- under the box, its sides and top, and its edges. A box stands in a frame of its own, such as a lift's,
-- see shared/lift.lua. Nothing here runs by itself; the loop that wants a box draws it every frame
LiftDraw = {}

-- Metres off the floor the tint and the lines are drawn, so they do not flicker in it
local tintLift = 0.02
local lineLift = 0.03

---@alias LiftColour {[1]: integer, [2]: integer, [3]: integer, [4]: integer}

---@class LiftBoxColours
---@field floor LiftColour @ The tint on the floor under it
---@field side LiftColour
---@field edge LiftColour

---@param a vector3
---@param b vector3
---@param c vector3
---@param d vector3
---@param colour LiftColour
function LiftDraw.quad(a, b, c, d, colour)
    local red, green, blue, alpha = colour[1], colour[2], colour[3], colour[4]

    -- Both faces, since a poly is only seen from one side
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, red, green, blue, alpha)
    DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, red, green, blue, alpha)
    DrawPoly(c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, red, green, blue, alpha)
    DrawPoly(d.x, d.y, d.z, c.x, c.y, c.z, a.x, a.y, a.z, red, green, blue, alpha)
end

---@param a vector3
---@param b vector3
---@param colour LiftColour
function LiftDraw.line(a, b, colour)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, colour[1], colour[2], colour[3], colour[4])
end

-- A box standing on the floor of a frame, about its origin
---@param frame {coords: vector3, heading: number}
---@param half vector2 @ Half its size across and along the frame
---@param height number @ Metres
---@param colours LiftBoxColours
function LiftDraw.box(frame, half, height, colours)
    ---@param z number
    ---@return vector3 a @ The corners round it at that height
    ---@return vector3 b
    ---@return vector3 c
    ---@return vector3 d
    local function getCorners(z)
        return GetLiftWorld(frame, vec3(-half.x, -half.y, z)), GetLiftWorld(frame, vec3(half.x, -half.y, z)), GetLiftWorld(frame, vec3(half.x, half.y, z)), GetLiftWorld(frame, vec3(-half.x, half.y, z))
    end

    local tintA, tintB, tintC, tintD = getCorners(tintLift)
    local a, b, c, d = getCorners(lineLift)
    local e, f, g, h = getCorners(height)

    LiftDraw.quad(tintA, tintB, tintC, tintD, colours.floor)

    for _, side in ipairs({{a, b, f, e}, {b, c, g, f}, {c, d, h, g}, {d, a, e, h}, {e, f, g, h}}) do
        LiftDraw.quad(side[1], side[2], side[3], side[4], colours.side)
    end

    for _, edge in ipairs({{a, b}, {b, c}, {c, d}, {d, a}, {a, e}, {b, f}, {c, g}, {d, h}, {e, f}, {f, g}, {g, h}, {h, e}}) do
        LiftDraw.line(edge[1], edge[2], colours.edge)
    end
end