--- H5 creatures: small helpers shared by area ability scripts (hex distance, lines, fans, normal attack damage, marks, trigger chance).
--- Only used via require("heroes-memorial.h5:combat/h5Area"), not registered as a script.

local M = {}
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)

M.W = 17
M.MARK = "H5_AREA_MARK_H5C"

function M.hexIndex(hex)
	return hex:getX() + hex:getY() * M.W
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

--- Shortest distance between two stacks (over every hex they occupy)
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

function M.unitHexDistance(u, hex)
	local hs = u:getHexes()
	local best = 1000
	for i = 1, hs:size() do best = math.min(best, M.hexDistance(hs:at(i), hex)) end
	return best
end

--- The hex of a stack nearest to another stack
function M.nearestHex(u, toward)
	local hs = u:getHexes()
	local best, bestHex = 1000, u:getPosition()
	for i = 1, hs:size() do
		local d = M.unitHexDistance(toward, hs:at(i))
		if d < best then best, bestHex = d, hs:at(i) end
	end
	return bestHex
end

--- Hex lookup for the whole field: key = hex index
function M.hexTable(battle)
	local arr = battle:getAllPossibleHexes()
	local t = {}
	for i = 1, arr:size() do
		local h = arr:at(i)
		t[M.hexIndex(h)] = h
	end
	return t
end

local function toCube(hex)
	local u = hex:getX() + math.floor(hex:getY() / 2)
	local v = hex:getY()
	return u - v, -u, v
end

local function roundCube(x, y, z)
	local rx, ry, rz = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
	local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
	if dx > dy and dx > dz then
		rx = -ry - rz
	elseif dy > dz then
		ry = -rx - rz
	else
		rz = -rx - ry
	end
	return rx, ry, rz
end

--- Draws a line from a to b and returns the hex index of step k (0 = a, n = b, k may exceed n, extending the line). nil when off the battlefield.
function M.lineIndex(a, b, k)
	local ax, ay, az = toCube(a)
	local bx, by, bz = toCube(b)
	local n = M.hexDistance(a, b)
	if n == 0 then return nil end
	local t = k / n
	local x = ax + (bx - ax) * t + 1e-6
	local y = ay + (by - ay) * t + 2e-6
	local z = az + (bz - az) * t - 3e-6
	local rx, ry, rz = roundCube(x, y, z)
	local v = rz
	local u = -ry
	local col = u - math.floor(v / 2)
	if v < 0 or v > 10 or col < 1 or col > 15 then return nil end
	return col + v * M.W
end

--- The stack on a hex (alive, not in ghost state)
function M.unitAt(battle, hexes, index)
	local h = hexes[index]
	if h == nil then return nil end
	local u = battle:getUnitByPos(h, true)
	if u == nil or not u:isAlive() or u:isGhost() then return nil end
	return u
end

function M.isEnemyOf(u, side)
	return u:getSide() ~= side and u:isAlive() and not u:isGhost() and not u:isTurret()
end

--- Enemies as seen by actor (hypnotized stacks count for the controlling side, as newer engines do)
function M.hostile(battle, actor, u)
	return battle:isHostile(actor, u) and u:isAlive() and not u:isGhost() and not u:isTurret()
end

--- Can take damage: alive, not a ghost, not an arrow tower, not invincible
function M.damageable(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret() and not u:isInvincible()
end

local function rollBase(server, attacker, ranged)
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
	return base
end

--- Normal attack damage: count x random damage x attack/defense factor (same as the engine's H3 formula) x pct%
function M.attackDamage(server, attacker, target, pct, ranged)
	local base = rollBase(server, attacker, ranged)
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * pct / 100))
end

--- Only count and random damage, ignoring Attack and Defense
function M.rawDamage(server, unit, pct, ranged)
	return math.max(1, math.floor(rollBase(server, unit, ranged or false) * pct / 100))
end

--- Deals damage and plays the animation (animation deferred, in step with the damage)
function M.hit(server, battle, target, amount, animation, sound)
	if not M.damageable(target) or amount <= 0 then return 0, 0 end
	if animation then
		server:showBattleAnimation(battle, { { unit = target } }, animation, sound or "", 1.0, true)
	end
	-- The engine needs at least 1 damage per hit; this is >= 1 anyway
	return server:damageUnit(battle, target, amount)
end

--- Hidden mark: read the value, nil if absent
function M.markValue(unit, key)
	local list = unit:getBonuses({ type = M.MARK })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if b:getStacking() == key then return b:getVal() end
	end
	return nil
end

function M.clearMark(server, battle, unit, key)
	local list = unit:getBonuses({ type = M.MARK }):filter(function(b) return b:getStacking() == key end)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

--- Attach a mark. turns = nil means the whole battle
function M.setMark(server, battle, unit, key, val, turns)
	M.clearMark(server, battle, unit, key)
	local d = {
		type       = M.MARK,
		val        = val,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		stacking   = key,
		hidden     = true
	}
	if turns then
		d.duration = ENUM.BonusDuration.nTurns
		d.turns = turns
	else
		d.duration = ENUM.BonusDuration.oneBattle
	end
	server:addUnitBonus(battle, unit, d, true)
end

--- A script ability on the creature (COMBAT_EVENT_TRIGGER, subtype ending in name); returns that bonus if present (the one with the largest value)
function M.ability(unit, name)
	local best = nil
	local list = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local sub = b:getSubtype() or ""
		if sub == name or sub:sub(-(#name + 1)) == ":" .. name then
			if best == nil or b:getVal() > best:getVal() then best = b end
		end
	end
	return best
end

--- Has a given bonus type (pcall returns false when a custom type is not found)
function M.has(unit, bonusType)
	local ok, v = pcall(function() return unit:hasBonuses({ type = bonusType }) end)
	return ok and v == true
end

function M.isDemon(unit)
	return M.has(unit, "tears-of-ashan:DEMONIC") or M.has(unit, "DEMONIC")
end

function M.isUndead(unit)
	return M.has(unit, "UNDEAD")
end

--- Fire immunity (school immunity); true means no Fire damage at all
function M.fireImmune(unit)
	local list = unit:getBonuses({ type = "SPELL_SCHOOL_IMMUNITY" })
	for i = 1, list:size() do
		local sub = list:getBonus(i):getSubtype() or ""
		if sub == "fire" or sub:sub(-5) == ".fire" or sub:sub(-5) == ":fire" then return true end
	end
	return false
end

--- Immunity to a school (SPELL_SCHOOL_IMMUNITY of that school or any); school is air / fire / water / earth
function M.schoolImmune(unit, school)
	local list = unit:getBonuses({ type = "SPELL_SCHOOL_IMMUNITY" })
	local n = #school
	for i = 1, list:size() do
		local sub = list:getBonus(i):getSubtype() or ""
		if sub == school or sub:sub(-(n + 1)) == "." .. school or sub:sub(-(n + 1)) == ":" .. school
			or sub == "any" or sub:sub(-4) == ".any" then return true end
	end
	return false
end

--- Fire damage reduction percent (positive reduces, negative is vulnerability)
function M.fireReduction(unit)
	local total = 0
	local list = unit:getBonuses({ type = "SPELL_DAMAGE_REDUCTION" })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local sub = b:getSubtype() or ""
		if sub == "fire" or sub:sub(-5) == ".fire" or sub:sub(-5) == ":fire" or sub == "any" or sub:sub(-4) == ".any" then
			total = total + b:getVal()
		end
	end
	return total
end

--- Chance bonus of Deduction (changechanceskill), 0 when not installed
function M.chanceBoost(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "CHANGECHANCE_BOOST" }) end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 0
end

--- H5 trigger chance (inferred formula, see the design document): base 25% x sqrt(attacker total health / defender total health),
--- times the trigger factor, limited to 5%-75%, then times the Deduction bonus. Returns an integer percent.
function M.procChance(attacker, defender, procFactor, defenderHealth)
	-- H5 original (note on the Russian wiki page Мечник (HoMM V)):
	-- attacker total health > defender: base = 0.25 + 0.03 x att/def; otherwise base = 0.25 - 0.03 x def/att; base limited to [0.05, 0.75]
	-- chance = 1 - (1 - base)^trigger factor
	local atk = math.max(1, attacker:getAvailableHealth())
	local def = defenderHealth or defender:getAvailableHealth()
	if def == nil or def < 1 then def = 1 end
	local base
	if atk > def then base = 0.25 + 0.03 * (atk / def) else base = 0.25 - 0.03 * (def / atk) end
	if base < 0.05 then base = 0.05 end
	if base > 0.75 then base = 0.75 end
	local p = (1 - (1 - base) ^ (procFactor or 1)) * 100
	p = p * (100 + M.chanceBoost(attacker)) / 100
	if p > 100 then p = 100 end
	return math.floor(p + 0.5)
end

function M.roll(server, battle, unit, chance)
	if chance >= 100 then return true end
	if chance <= 0 then return false end
	local ok, r = pcall(function() return server:rollCombatAbility(battle, unit, chance) end)
	if ok and type(r) == "boolean" then return r end
	return server:rngInt(1, 100) <= chance
end

--- Main target of this hit (the first target in the attack event is the main target)
function M.primary(payload, other)
	local t = payload and payload.targets and payload.targets[1]
	if t and t.unit then return t.unit, t end
	return other, nil
end

function M.name(unit)
	return unit:getCreature():getNameTextID(unit:getCount())
end

--- Move distance record: the start is noted before moving (hex index + 1), the straight-line hexes walked after moving, cleared at the end of the action
M.MV_FROM = "h5MvFrom"
M.MV_DIST = "h5MvDist"

function M.beforeMove(server, battle, unit)
	local pos = unit:getPosition()
	if pos == nil or not pos:isValid() then return end
	M.setMark(server, battle, unit, M.MV_FROM, M.hexIndex(pos) + 1, 1)
end

function M.afterMove(server, battle, unit)
	local from = M.markValue(unit, M.MV_FROM)
	if from == nil or from <= 0 then return end
	local start = M.hexTable(battle)[from - 1]
	local pos = unit:getPosition()
	if start == nil or pos == nil then return end
	local d = M.hexDistance(start, pos)
	local before = M.markValue(unit, M.MV_DIST) or 0
	-- Returning after the strike (RETURN_AFTER_STRIKE) is another move; only the first is recorded
	if before > 0 then return end
	M.setMark(server, battle, unit, M.MV_DIST, d, 1)
end

function M.moved(unit)
	return M.markValue(unit, M.MV_DIST) or 0
end

function M.movedFrom(battle, unit)
	local from = M.markValue(unit, M.MV_FROM)
	if from == nil or from <= 0 then return nil end
	return M.hexTable(battle)[from - 1]
end

function M.clearMove(server, battle, unit)
	M.clearMark(server, battle, unit, M.MV_FROM)
	M.clearMark(server, battle, unit, M.MV_DIST)
end

return M
