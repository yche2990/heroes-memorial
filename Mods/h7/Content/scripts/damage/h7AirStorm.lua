local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Damage rules of Erratic Storm (H7, Heroes VII creatures and spells batch SA), appended to core:damageCalculator:
---   1. a shooter standing in a storm area (obstacles placed by the spell h7ErraticStorm) shoots with Attack -X (X = value of the hidden mark H7_AIRSTORM_H7C on the shooter);
---   2. if the line of fire (the straight line from the shooter's hex to the target's hex, target hex included, shooter hex excluded) crosses a storm area: only 10% of the damage remains.
--- Only shooters carrying the H7_AIRSTORM_H7C mark check the obstacles (the mark is put on all stacks on the field at cast time and expires with the storm),
--- so battles without a storm cost only one extra table lookup.

local W = 17
local MARK = "H7_AIRSTORM_H7C"
local SPELL = "h7ErraticStorm"

local function hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
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

--- Indices of hexes crossed by the straight line between two hexes (both ends excluded)
local function between(a, b)
	local out = {}
	local n = hexDistance(a, b)
	if n <= 1 then return out end
	local ax, ay, az = toCube(a)
	local bx, by, bz = toCube(b)
	for k = 1, n - 1 do
		local t = k / n
		local _, ry, rz = roundCube(ax + (bx - ax) * t + 1e-6, ay + (by - ay) * t + 2e-6, az + (bz - az) * t - 3e-6)
		out[#out + 1] = (-ry - math.floor(rz / 2)) + rz * W
	end
	return out
end

local function isStorm(o)
	local s = o:getSpell()
	if s == nil then return false end
	return string.find(s:getJsonKey(), SPELL, 1, true) ~= nil
end

local function stormOn(battle, hex)
	for _, o in ipairs(battle:getObstaclesOnPos(hex, false) or {}) do
		if isStorm(o) then return true end
	end
	return false
end

local function anyStorm(battle)
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		if isStorm(o) then return true end
	end
	return false
end

function Script:getAttack(info)
	local base = Base.getAttack(self, info)
	if not info.shooting then return base end
	if not self:hasBonusOfType(info.attackerBonuses, MARK) then return base end
	-- H7 audit B4: X is taken from the storm the shooter stands in (mark stacking "h7AirStorm@anchor hex"; the old "h7AirStorm" is added by the AI simulation and counts for any storm)
	local marks = info.attacker:getBonuses({ type = MARK })
	local x = 0
	local hexes = info.attacker:getHexes()
	for i = 1, hexes:size() do
		for _, o in ipairs(info.battle:getObstaclesOnPos(hexes:at(i), false) or {}) do
			if isStorm(o) then
				local p = o:getPosition()
				local key = "h7AirStorm@" .. tostring(p:getX() + p:getY() * W)
				for j = 1, marks:size() do
					local b = marks:getBonus(j)
					local st = b:getStacking()
					if (st == key or st == "h7AirStorm") and b:getVal() > x then x = b:getVal() end
				end
			end
		end
	end
	if x <= 0 then return base end
	return base - x
end

function Script:getH7AirStormFactor(info)
	if not info.shooting then return 0 end
	if not self:hasBonusOfType(info.attackerBonuses, MARK) then return 0 end
	local battle = info.battle
	if not anyStorm(battle) then return 0 end
	local a = info.attackerHex or info.attacker:getPosition()
	local d = info.defenderHex or info.defender:getPosition()
	if a == nil or d == nil then return 0 end
	local cells = between(a, d)
	cells[#cells + 1] = d:getX() + d:getY() * W
	local want = {}
	for _, k in ipairs(cells) do want[k] = true end
	local all = battle:getAllPossibleHexes()
	for i = 1, all:size() do
		local h = all:at(i)
		if want[h:getX() + h:getY() * W] and stormOn(battle, h) then return -0.9 end
	end
	return 0
end

Script:declareBonus(MARK)
Script:addDamageFactor("getH7AirStormFactor")

return Script
