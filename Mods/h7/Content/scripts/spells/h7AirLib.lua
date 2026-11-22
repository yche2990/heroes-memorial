--- Helpers shared by the H7 Air spells (batch SA) (not registered as a script; required by the h7Air* scripts)
--- Distances and lines are the same as the engine's BattleHex::getDistance.

local M = {}

M.W = 17
M.DIRS = { "copyToNorthWest", "copyToNorthEast", "copyToEast", "copyToSouthEast", "copyToSouthWest", "copyToWest" }

function M.key(hex)
	return hex:getX() + hex:getY() * M.W
end

function M.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

function M.toList(arr)
	local list = {}
	for i = 1, arr:size() do list[#list + 1] = arr:at(i) end
	return list
end

--- Distance between the nearest hexes of two stacks (1 = adjacent)
function M.unitDistance(a, b)
	local ha, hb = M.toList(a:getHexes()), M.toList(b:getHexes())
	local best = 1000
	for _, x in ipairs(ha) do
		for _, y in ipairs(hb) do
			local d = M.hexDistance(x, y)
			if d < best then best = d end
		end
	end
	return best
end

--- Living stacks adjacent to unit (itself, ghosts and arrow towers excluded); filter can narrow further
function M.adjacentUnits(battle, unit, filter)
	local id = unit:unitID()
	return battle:getUnitsIf(function(u)
		if u:unitID() == id or not u:isAlive() or u:isGhost() or u:isTurret() then return false end
		if M.unitDistance(u, unit) ~= 1 then return false end
		if filter and not filter(u) then return false end
		return true
	end)
end

--- All hexes within radius r of center (center included), valid hexes only
function M.hexesAround(center, r)
	local out, seen = { center }, { [M.key(center)] = true }
	local frontier = { center }
	for _ = 1, r do
		local nextF = {}
		for _, h in ipairs(frontier) do
			for _, dir in ipairs(M.DIRS) do
				local n = h[dir](h)
				if n:isValid() and not seen[M.key(n)] then
					seen[M.key(n)] = true
					out[#out + 1] = n
					nextF[#nextF + 1] = n
				end
			end
		end
		frontier = nextF
	end
	return out
end

local function toCube(hex)
	local u = hex:getX() + math.floor(hex:getY() / 2)
	local v = hex:getY()
	return u - v, -u, v
end

local function roundCube(x, y, z)
	local rx, ry, rz = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
	local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
	if dx > dy and dx > dz then rx = -ry - rz elseif dy > dz then ry = -rx - rz else rz = -rx - ry end
	return rx, ry, rz
end

--- Hexes crossed by the straight line between two hexes (both ends excluded), returned as a list of hex indices (x + y*17)
function M.between(a, b)
	local out = {}
	local n = M.hexDistance(a, b)
	if n <= 1 then return out end
	local ax, ay, az = toCube(a)
	local bx, by, bz = toCube(b)
	for k = 1, n - 1 do
		local t = k / n
		local _, ry, rz = roundCube(ax + (bx - ax) * t + 1e-6, ay + (by - ay) * t + 2e-6, az + (bz - az) * t - 3e-6)
		local v = rz
		local col = -ry - math.floor(v / 2)
		out[#out + 1] = col + v * M.W
	end
	return out
end

function M.has(unit, t)
	local ok, r = pcall(function() return unit:hasBonuses({ type = t }) end)
	return ok and r
end

--- War machines and arrow towers: not pushed, not relocated
function M.immovable(u)
	if u:isTurret() then return true end
	if M.has(u, "SIEGE_WEAPON") then return true end
	return false
end

--- Stack moves one hex from pos in direction dir; nil if it cannot (as step of h47Shove)
function M.step(battle, unit, pos, hexes, dir)
	local newPos = pos[dir](pos)
	if not newPos:isValid() or not newPos:isAvailable() then return nil end
	local newHexes = {}
	for i, h in ipairs(hexes) do
		local n = h[dir](h)
		if not n:isValid() or not n:isAvailable() then return nil end
		newHexes[i] = n
	end
	if not battle:isAccessibleForUnit(unit, newPos) then return nil end
	if battle:hasPenaltyOnLine(pos, newPos, true, false) then return nil end
	return newPos, newHexes
end

--- Move at most n hexes along dir; returns the end point and how many hexes were moved
function M.slide(battle, unit, dir, n)
	local p, hs = unit:getPosition(), M.toList(unit:getHexes())
	local moved = 0
	for _ = 1, n do
		local np, nh = M.step(battle, unit, p, hs, dir)
		if np == nil then break end
		p, hs = np, nh
		moved = moved + 1
	end
	return p, moved
end

--- Side converted to 0 (attacker) / 1 (defender), so it can go into bonus parameters
function M.sideNum(side)
	if side == ENUM.BattleSide.attacker then return 0 end
	return 1
end

return M
