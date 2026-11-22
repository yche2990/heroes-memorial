--- Tsunami (H7): all stacks (friend or foe) in the area centered on the target hex's row, 2 rows above and below (5 rows in all) across the whole width of the battlefield,
--- take Water damage; then surviving single-hex stacks are pushed 2 hexes away from the casting side (stopping when blocked by stacks, obstacles or the edge).
--- Damage = base[mastery] + perPower[mastery] x Spell Power (average of H7's minimum and maximum damage), then through the engine's spell damage adjustments (school reduction, resistance etc.).
--- At cast time a full-battlefield wave plays first on its own (animLeft when the caster is on the left, animRight on the right), then damage and pushing are settled.
--- Parameters: base, perPower (4 numbers, none/basic/advanced/expert), rows (half the number of rows of the area, default 2), push (hexes pushed, default 2),
---       animLeft, animRight, sound
local Base = require("spells/damage")
local Lib = require("heroes-memorial.h7:spells/h7SWLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:describeTargetStep()
	return nil
end

local function centerHex(aimPoint, spellTarget)
	for _, list in ipairs({ spellTarget or {}, aimPoint or {} }) do
		for _, dest in ipairs(list) do
			if dest.hex ~= nil and dest.hex:isValid() then return dest.hex end
			if dest.unit ~= nil then return dest.unit:getPosition() end
		end
	end
	return nil
end

function Script:inBand(center, hex)
	return math.abs(hex:getY() - center:getY()) <= (self.rows or 2)
end

function Script:unitInBand(center, unit)
	local hs = unit:getHexes()
	for i = 1, hs:size() do
		if self:inBand(center, hs:at(i)) then return true end
	end
	return false
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local center = centerHex(aimPoint, spellTarget)
	if center == nil then return {} end
	local battle = mechanics:getBattle()
	local units = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret()
			and self:isValidTarget(mechanics, u) and self:isReceptive(mechanics, u)
			and self:unitInBand(center, u)
	end)
	local result = {}
	for _, u in ipairs(units) do table.insert(result, { unit = u, hex = u:getPosition() }) end
	return result
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local center = centerHex(nil, spellTarget)
	if center == nil then return hexes end
	local all = mechanics:getBattle():getAllPossibleHexes()
	for i = 1, all:size() do
		local h = all:at(i)
		if self:inBand(center, h) then hexes:insert(h) end
	end
	return hexes
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local raw = Lib.pick(self.base, lvl) + Lib.pick(self.perPower, lvl) * sp
	local ev = mechanics:getEffectValue() or 0
	if ev <= 0 then return math.floor(raw) end
	return math.floor(raw * mechanics:adjustEffectValue(unit) / ev)
end

--- Push a single-hex stack steps hexes along dir
local function push(server, battle, unit, dir, steps)
	if not unit:isAlive() or unit:getHexes():size() ~= 1 then return false end
	local start = unit:getPosition()
	local hex = start
	for _ = 1, steps do
		local nxt = hex[dir](hex)
		if nxt == nil or not nxt:isValid() or not nxt:isAvailable() or not battle:isAccessibleForUnit(unit, nxt) then break end
		hex = nxt
	end
	if hex:getX() == start:getX() and hex:getY() == start:getY() then return false end
	server:moveUnit(battle, unit, hex, true)
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local side = mechanics:getCasterSide()
	local leftCaster = (side == 0) or (side == "attacker")
	if server:describeChanges() then
		local ref = nil
		for _, dest in ipairs(target) do
			if dest.unit ~= nil then ref = dest.unit:getPosition() break end
		end
		ref = ref or Lib.anyHex(battle)
		Lib.fieldAnim(server, battle, ref, leftCaster and self.animLeft or self.animRight, self.sound)
	end

	Base.apply(self, mechanics, server, target)

	-- Pushing: with the caster on the left, push east. Stacks farthest from the caster go first so those in front do not block those behind
	local dir = leftCaster and "copyToEast" or "copyToWest"
	local alive = {}
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u ~= nil and u:isAlive() and not u:isGhost() and u:getHexes():size() == 1
			and not u:hasBonuses({ type = "SIEGE_WEAPON" }) then
			table.insert(alive, u)
		end
	end
	table.sort(alive, function(a, b)
		if leftCaster then return a:getPosition():getX() > b:getPosition():getX() end
		return a:getPosition():getX() < b:getPosition():getX()
	end)
	local moved = false
	for _, u in ipairs(alive) do
		if push(server, battle, u, dir, self.push or 2) then moved = true end
	end
	if moved then server:refreshBattleUnits(battle) end
end

return Script
