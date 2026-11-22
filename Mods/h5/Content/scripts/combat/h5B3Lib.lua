--- Small helpers shared by the B3 group of scripts of H5 Creatures (heroes-memorial.h5). Only required, not registered as a script.
--- Chances and pushing back on the initiative bar use combat/h5Common directly.

local C = require("combat/h5Common")
local M = {}

--- Bonus of Deduction (changechanceskill): when not installed this type is not found and counts as 0
function M.chanceBoost(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "CHANGECHANCE_BOOST" }) end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 0
end

--- Chance (%) of H5 probability-based abilities, always via h5Common.procChance
function M.procChance(actor, target, pf)
	return C.procChance(actor, target, pf)
end

--- The bonus type may come from another mod (querying it errors when that mod is off); treated as absent
function M.has(unit, filter)
	local ok, r = pcall(function() return unit:hasBonuses(filter) end)
	return ok and r == true
end

function M.value(unit, filter)
	local ok, r = pcall(function() return unit:getBonusesValue(filter) end)
	if ok and type(r) == "number" then return r end
	return 0
end

function M.bonuses(unit, filter)
	local ok, r = pcall(function() return unit:getBonuses(filter) end)
	if ok then return r end
	return nil
end

--- Same as the engine's BattleHex::getDistance
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

function M.unitDistance(a, b)
	local ha, hb = a:getHexes(), b:getHexes()
	local best = 1000
	for i = 1, ha:size() do
		for j = 1, hb:size() do
			best = math.min(best, M.hexDistance(ha:at(i), hb:at(j)))
		end
	end
	return best
end

function M.adjacent(a, b)
	local around = a:getSurroundingHexes()
	local hexes = b:getHexes()
	for i = 1, hexes:size() do
		if around:contains(hexes:at(i)) then return true end
	end
	return false
end

--- Stacks that count as "real troops": alive, not an arrow tower, war machine or clone
function M.isRealUnit(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret() and not u:isClone()
		and not u:hasBonuses({ type = "SIEGE_WEAPON" })
end

function M.isSummoned(u)
	local ok, r = pcall(function() return u:copy():isSummoned() end)
	return ok and r == true
end

--- Normal attack damage estimate: count x random damage x attack/defense factor x pct%
function M.attackDamage(server, attacker, target, pct, ranged)
	local count = attacker:getCount()
	local minDamage = attacker:getMinDamage(ranged)
	local maxDamage = math.max(minDamage, attacker:getMaxDamage(ranged))
	local base = 0
	if count <= 10 then
		for _ = 1, count do base = base + server:rngInt(minDamage, maxDamage) end
	else
		for _ = 1, 10 do base = base + server:rngInt(minDamage, maxDamage) end
		base = base * count / 10
	end
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * pct / 100))
end

--- H5 "push back on the initiative bar by 1.0" (Intimidation, Bear Roar): as h5Common.resetAtb, a stack that has not acted this round cannot act this round
function M.delayTurn(server, battle, unit)
	C.resetAtb(server, battle, unit)
end

--- Blood Rage event: makes the Blood Rage script (h5DemonRage) add or remove rage for this stack at the end of its action. Other scripts may also attach this hidden bonus
function M.rageEvent(server, battle, unit, delta)
	if unit == nil or not unit:isAlive() then return end
	if not M.has(unit, { type = "H5_DEMON_RAGED_H5C" }) then return end
	server:addUnitBonus(battle, unit, {
		type = "H5_RAGE_EVENT_H5C", val = delta,
		duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		sourceID = unit:getCreature():getJsonKey(),
		hidden = true
	}, true)
end

function M.shortKey(creature)
	local k = creature:getJsonKey()
	local i = string.find(k, ":", 1, true)
	if i then return string.sub(k, i + 1) end
	return k
end

--- Short id used to look stacks up in tables: copied creatures (shrunk or downgraded versions) read the source mark, see h5Common.sourceKey
function M.unitShortKey(unit)
	return C.sourceShortKey(unit)
end

return M
