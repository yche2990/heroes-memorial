--- kadAiProxy: small helpers shared by AI evaluation branches
---
--- When the AI (BattleAI / MMAI, including neutrals and players' auto-combat) decides whether to use an ability, it runs the spell effect on an imaginary battlefield
--- (server:describeChanges() is false then) and compares every unit's battle value before and after. Moving units, obstacles, custom markers and combat scripts
--- are all worth 0 there, and harming own units vetoes the cast. Evaluation branch: when describeChanges() is false, skip the real effect and apply an equivalent
--- the AI understands (damage to enemies / native bonuses, the proxy value), then return. Real casts (describeChanges() true) use the real effect;
--- what the player sees and the descriptions do not change.
---
--- Proxy values are expressed as equivalent damage to a target (health points): dealing D to a stack lowers its value by about unit value x D / unit health,
--- the same scale the AI uses for normal attacks, so it compares directly with "just attack".
---
--- A file of this name is shipped in every mod that uses it (scripts/lib/kadAiProxy.lua); copies are kept identical in logic,
--- so no dependency is added. Use the evaluation branch only in apply of active ability spells; not in obstacle trigger spells or combat scripts
--- (the AI also evaluates trigger spells when estimating obstacle damage). P.isAi can be used in combat scripts.

local P = {}
P.VERSION = 1

--- is this an AI evaluation
function P.trial(server)
	return not server:describeChanges()
end

--- unit value: the creature's aiValue (only read for ratios, never changed), at least 1
function P.value(u)
	local ok, v = pcall(function() return u:getCreature():getAIValue() end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 1
end

--- value -> health points of target t
function P.hpOf(value, t)
	return value / P.value(t) * t:getMaxHealth()
end

--- value of losing `count` units of creature `lost`, as health points of target t (cost of hurting own side)
function P.costHp(lost, count, t)
	return P.hpOf(P.value(lost) * count, t)
end

--- immunity (four kinds: spell, school, negative, level); invincibility counts too. o = { spell = "mod:key", school = "water", negative = true, level = 1..5 }
function P.immune(u, o)
	o = o or {}
	if u:isInvincible() then return true end
	if o.spell then
		local short = string.gsub(o.spell, "^.*:", "")
		if u:hasBonuses({ type = "SPELL_IMMUNITY", subtype = short }) then return true end
		local ok, r = pcall(function() return u:hasBonuses({ type = "SPELL_IMMUNITY", subtype = o.spell }) end)
		if ok and r then return true end
	end
	if o.school then
		if u:hasBonuses({ type = "SPELL_SCHOOL_IMMUNITY", subtype = o.school }) then return true end
		if u:hasBonuses({ type = "SPELL_SCHOOL_IMMUNITY", subtype = "any" }) then return true end
		if o.negative and u:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = o.school }) then return true end
	end
	if o.negative and u:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "any" }) then return true end
	if o.level and u:getBonusesValue({ type = "LEVEL_SPELL_IMMUNITY" }) >= o.level then return true end
	return false
end

--- enemies the actor can attack
function P.hostile(battle, actor, u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret() and battle:isHostile(actor, u)
end

--- proxy damage: none if immune or below 1, capped at remaining health. Returns the amount dealt
function P.damage(server, battle, t, hp, o)
	hp = math.floor(hp or 0)
	if t == nil or not t:isAlive() or t:isGhost() or hp < 1 or P.immune(t, o) then return 0 end
	hp = math.min(hp, t:getAvailableHealth())
	server:damageUnit(battle, t, hp)
	return hp
end

--- proxy buff for own side (F5): add a native bonus and let the engine value it. d is the bonus description; source defaults to other, hidden
function P.buff(server, battle, u, d)
	if u == nil or not u:isAlive() then return end
	d.sourceType = d.sourceType or ENUM.BonusSource.other
	if d.hidden == nil then d.hidden = true end
	if d.turns and not d.duration then d.duration = ENUM.BonusDuration.nTurns end
	server:addUnitBonus(battle, u, d, true)
end

--- control (F4): disabling for `turns` rounds, as a share of target total health min(turns, 8)/8 x severity
function P.controlRatio(turns, severity)
	return math.min(math.max(turns or 1, 0), 8) / 8 * (severity or 1)
end

--- expected damage of one normal attack (no dice): count x average damage x attack/defense factor (H3 formula) x pct%
function P.attackEstimate(attacker, target, pct, ranged)
	if attacker == nil or target == nil then return 0 end
	ranged = ranged or false
	local lo = attacker:getMinDamage(ranged)
	local hi = math.max(lo, attacker:getMaxDamage(ranged))
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local f
	if diff > 0 then f = 1 + 0.05 * math.min(diff, 60) else f = 1 - 0.025 * math.min(-diff, 28) end
	return attacker:getCount() * (lo + hi) / 2 * f * (pct or 100) / 100
end

--- distance between two hexes
function P.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then return math.max(math.abs(dx), math.abs(dy)) end
	return math.abs(dx) + math.abs(dy)
end

--- shortest distance from any hex of a unit to hex
function P.unitDistance(u, hex)
	local best = 99
	local hs = u:getHexes()
	for i = 1, hs:size() do best = math.min(best, P.hexDistance(hs:at(i), hex)) end
	return best
end

--- shortest distance between two units (1 = adjacent)
function P.unitsDistance(a, b)
	local best = 99
	local hs = a:getHexes()
	for i = 1, hs:size() do best = math.min(best, P.unitDistance(b, hs:at(i))) end
	return best
end

--- enemies (relative to actor) within radius of the centre hex
function P.hostilesNear(battle, actor, center, radius)
	return battle:getUnitsIf(function(u)
		return P.hostile(battle, actor, u) and P.unitDistance(u, center) <= radius
	end)
end

--- units adjacent to unit that satisfy pred
function P.adjacent(battle, unit, pred)
	return battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and u:unitID() ~= unit:unitID() and P.unitsDistance(u, unit) == 1
			and (pred == nil or pred(u))
	end)
end

--- shooter (with ammo)
function P.shooter(u)
	return u:isShooter()
end

--- nearest enemy of unit
function P.nearestHostile(battle, unit)
	local best, bd = nil, 99
	for _, u in ipairs(battle:getUnitsIf(function(x) return P.hostile(battle, unit, x) end)) do
		local d = P.unitsDistance(unit, u)
		if d < bd then best, bd = u, d end
	end
	return best, bd
end

--- total value of a side (sum of unit value x count)
function P.armyValue(battle, pred)
	local total = 0
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isTurret() and pred(x) end)) do
		total = total + P.value(u) * u:getCount()
	end
	return total
end

--- is actor's side winning: own / enemy value >= ratio (default 1.5)
function P.winning(battle, actor, ratio)
	local own = P.armyValue(battle, function(x) return not battle:isHostile(actor, x) end)
	local foe = P.armyValue(battle, function(x) return battle:isHostile(actor, x) end)
	return foe <= 0 or own >= foe * (ratio or 1.5)
end

--- by battle side (for hero casts without a casting unit): is side winning (own / enemy value >= ratio, default 1.5)
function P.winningSide(battle, side, ratio)
	local own = P.armyValue(battle, function(x) return x:getSide() == side end)
	local foe = P.armyValue(battle, function(x) return x:getSide() ~= side end)
	return foe <= 0 or own >= foe * (ratio or 1.5)
end

--- book value by battle side: put value on the opposing stack with the most health
function P.creditSide(server, battle, side, value)
	if value == nil or value <= 0 then return 0 end
	local best = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() and not x:isTurret() and x:getSide() ~= side end)) do
		if best == nil or u:getAvailableHealth() > best:getAvailableHealth() then best = u end
	end
	if best == nil then return 0 end
	return P.damage(server, battle, best, math.min(P.hpOf(value, best), best:getAvailableHealth() * 0.5))
end

--- book value (F10): put `value` on the actor's enemy stack with the most total health (it cannot die from this and does not skew other decisions)
function P.credit(server, battle, actor, value)
	if value == nil or value <= 0 then return 0 end
	local best = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return P.hostile(battle, actor, x) end)) do
		if best == nil or u:getAvailableHealth() > best:getAvailableHealth() then best = u end
	end
	if best == nil then return 0 end
	return P.damage(server, battle, best, math.min(P.hpOf(value, best), best:getAvailableHealth() * 0.5))
end

--- weak ability cap: at most 0.8 x the caster's expected damage of one attack on the nearest enemy (as target t health). Always attack if an enemy is reachable
function P.capWeak(hp, battle, caster, t)
	local e = P.nearestHostile(battle, caster)
	if e == nil then return hp end
	local atk = P.attackEstimate(caster, e, 100, caster:isShooter())
	local capHp = P.hpOf(atk / e:getMaxHealth() * P.value(e), t) * 0.8
	return math.min(hp, capHp)
end

--- sum of expected damage to unit from enemies that can reach it this round (all shooters; melee if distance - 1 <= speed)
function P.threat(battle, unit)
	local total = 0
	for _, e in ipairs(battle:getUnitsIf(function(x) return P.hostile(battle, unit, x) end)) do
		local ok, speed = pcall(function() return e:getBonusesValue({ type = "STACKS_SPEED" }) end)
		if not ok or type(speed) ~= "number" then speed = 0 end
		if e:isShooter() then
			total = total + P.attackEstimate(e, unit, 100, true)
		elseif P.unitsDistance(e, unit) - 1 <= speed then
			total = total + P.attackEstimate(e, unit, 100, false)
		end
	end
	return total
end

--- is the controller an AI: human returns false; neutral (no player) counts as AI; on API errors treat as human (do nothing, no effect on players)
local function notHuman(color)
	local ok, r = pcall(function() return GAME:playerIsHuman(color) end)
	return ok and r == false
end

--- is the unit's current controller an AI (hypnotize considered)
function P.isAi(battle, unit)
	local ok, color = pcall(function() return battle:getUnitController(unit) end)
	return ok and notHuman(color)
end

--- is the caster side an AI
function P.aiCaster(mechanics)
	local ok, color = pcall(function() return mechanics:getCasterColor() end)
	return ok and notHuman(color)
end

-- Exact bonus removal. The engine (BattleInfo::removeUnitBonus) compares only eight fields: duration, type, subtype, source,
-- value, source id, value type and propagation range, not stacking or remaining turns: removing one bonus also removes every other bonus on the unit
-- with the same eight fields (other stacking groups, added by other scripts). With source "other" the source id is always empty (the engine drops sourceID).
-- So count the bonuses that would be removed along with it first, and after removal restore the ones really lost as they were (stacking, turns, hidden unchanged).
-- Description text, icons and limiters cannot be read by scripts and cannot be restored: visible bonuses with descriptions must avoid clashes by a unique source / value.
-- Only bonuses with source "other" or "creature ability" are restored; for other sources (spell effects etc.) the same eight fields mean the same spell, removed as the engine does.
-- Usage: replace server:removeUnitBonuses(battle, unit, list) with P.removeExact(server, battle, unit, list).
local function exactKey(b)
	local dur = 0
	for _, d in ipairs(b:getDuration() or {}) do dur = dur + d end
	return table.concat({ b:getType(), b:getSubtype(), tostring(b:getSource()), b:getSourceID(), b:getVal(),
		tostring(b:getValType()), tostring(b:getEffectRange()), dur }, "|"), dur
end

-- subtype when restoring: names the engine reads back ("fire", "defence", "any") can be written as they are; custom subtypes read back as numbers,
-- -1 means no subtype (= damageTypeAll), damage 0 / 1 are written back as names, other numbers as they are (the engine accepts numbers and only notes it in the log)
local DAMAGE_SUB = { ["0"] = "damageTypeMelee", ["1"] = "damageTypeRanged" }
local DAMAGE_TYPES = { GENERAL_DAMAGE_REDUCTION = true, PERCENTAGE_DAMAGE_BOOST = true, FIRST_STRIKE = true }
local function restoreSubtype(b)
	local sub = b:getSubtype()
	if sub == nil or sub == "" or sub == "none" or sub == "-1" then return nil end
	local n = tonumber(sub)
	if n == nil then return sub end
	if DAMAGE_TYPES[b:getType()] and DAMAGE_SUB[sub] then return DAMAGE_SUB[sub] end
	return n
end

local RESTORABLE = { [ENUM.BonusSource.other] = true, [ENUM.BonusSource.creatureAbility] = true }

-- bonuses on the unit with the same eight fields that are not in list (counted by stacking + remaining turns)
local function bystanders(unit, list)
	local keys, types, inList = {}, {}, {}
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local k = exactKey(b)
		keys[k] = true
		inList[k .. "#" .. b:getStacking()] = true
		types[b:getType()] = true
	end
	local found = {}
	for t in pairs(types) do
		local all = unit:getBonuses({ type = t })
		for i = 1, all:size() do
			local b = all:getBonus(i)
			local k, dur = exactKey(b)
			if keys[k] and not inList[k .. "#" .. b:getStacking()] and RESTORABLE[b:getSource()] then
				local id = k .. "#" .. b:getStacking() .. "#" .. b:getTurnsRemain()
				local e = found[id]
				if e == nil then
					e = { n = 0, d = {
						type = b:getType(), val = b:getVal(), valueType = b:getValType(), effectRange = b:getEffectRange(),
						duration = dur, sourceType = b:getSource(), stacking = b:getStacking(), hidden = b:isHidden() } }
					local sub = restoreSubtype(b)
					if sub ~= nil then e.d.subtype = sub end
					if b:getSource() == ENUM.BonusSource.creatureAbility then e.d.sourceID = b:getSourceID() end
					if b:getTurnsRemain() > 0 then e.d.turns = b:getTurnsRemain() end
					found[id] = e
				end
				e.n = e.n + 1
			end
		end
	end
	return found
end

function P.removeExact(server, battle, unit, list)
	if unit == nil or list == nil or list:size() == 0 then return end
	local before = bystanders(unit, list)
	server:removeUnitBonuses(battle, unit, list)
	if next(before) == nil then return end
	local after = bystanders(unit, list)
	for id, e in pairs(before) do
		local left = after[id] and after[id].n or 0
		for _ = left + 1, e.n do
			local d = {}
			for k, v in pairs(e.d) do d[k] = v end
			server:addUnitBonus(battle, unit, d, true)
		end
	end
end

return P
