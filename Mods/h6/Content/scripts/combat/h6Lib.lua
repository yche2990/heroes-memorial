--- Heroes VI creatures and spells (heroes-memorial.h6): small helpers shared by the scripts. Only loaded with require("combat/h6Lib"), not registered as a script.
--- Written like h5Common / h5Area / h5AbLib of the Heroes V memorial, keeping only what the Heroes VI creatures need.
---
---   Hexes: W, hexIndex, hexDistance, unitDistance, hexTable, lineIndex (k-th step on the line from a to b), adjacent
---   Sides: hostile, real (alive, not a ghost, arrow tower or war machine), isUndead, isLiving
---   Damage: attackDamage (normal attack damage by the H3 formula x damage boost / reduction x pct%), damageModifier, hit (subtract health and play the animation)
---   Restoring: healedValue / addHealed (the "already restored" mark shared by the effects that restore damage after a hit; convention below)
---   Marks: markValue / setMark / clearMark (hidden bonus H6_MARK_H6C, kept apart by stacking group)
---   Bonuses: addBonus (source = creature ability), removeByStacking
---   Casts: useCast ("N times per battle / unlimited" done by refunding casts)
---   Battle log: log, name

local Proxy = require("lib/kadAiProxy") -- Round 354: some bonus removals use Proxy.removeExact (the engine ignores the stacking group when removing bonuses, so other marks of the same type and value would be removed too)
local M = {}

M.W = 17
M.MARK = "H6_MARK_H6C"
M.MOD = "heroes-memorial.h6"

-- ---- Hexes -------------------------------------------------------------------------------------

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

--- Shortest distance between the hexes occupied by two stacks (adjacent = 1)
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

--- Lookup table of all hexes: index -> BattleHex
function M.hexTable(battle)
	local arr = battle:getAllPossibleHexes()
	local t = {}
	for i = 1, arr:size() do
		local h = arr:at(i)
		t[M.hexIndex(h)] = h
	end
	return t
end

--- For transformTarget of spell effect scripts (inheriting spellEffect): the spellTarget the engine passes only has hexes (BattleSpellMechanics::transformSpellTarget);
--- attach the stack on each hex (living first, then corpses), each stack only once. Hexes without a stack stay as they are. Found in a cloud test on 2026-11-07
function M.unitTarget(mechanics, spellTarget)
	local battle = mechanics:getBattle()
	local out, seen = {}, {}
	for _, d in ipairs(spellTarget or {}) do
		local u = d.unit
		if u == nil and d.hex and d.hex:isValid() then u = battle:getUnitByPos(d.hex, true) or battle:getUnitByPos(d.hex, false) end
		if u ~= nil then
			if not seen[u:unitID()] then seen[u:unitID()] = true; out[#out + 1] = { unit = u, hex = d.hex } end
		else
			out[#out + 1] = d
		end
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
	if dx > dy and dx > dz then
		rx = -ry - rz
	elseif dy > dz then
		ry = -rx - rz
	else
		rz = -rx - ry
	end
	return rx, ry, rz
end

--- Draw a line from a to b and take the hex index of step k (k may exceed the distance, extending the line; returns nil off the board)
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

-- ---- Sides and kinds -------------------------------------------------------------------------------

function M.hostile(battle, actor, u)
	return battle:isHostile(actor, u) and u:isAlive() and not u:isGhost() and not u:isTurret()
end

function M.real(u)
	if u == nil or not u:isAlive() or u:isGhost() or u:isTurret() then return false end
	if u:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	return true
end

function M.isUndead(u) return u:hasBonuses({ type = "UNDEAD" }) end

function M.isLiving(u)
	return not (u:hasBonuses({ type = "UNDEAD" }) or u:hasBonuses({ type = "NON_LIVING" })
		or u:hasBonuses({ type = "MECHANICAL" }) or u:hasBonuses({ type = "SIEGE_WEAPON" }))
end

-- ---- Damage -------------------------------------------------------------------------------------

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

local function bonusSum(unit, selector, skip)
	local ok, v = pcall(function()
		local list = unit:getBonuses(selector)
		if skip then list = list:filter(function(b) return not skip(b) end) end
		return list:totalValue()
	end)
	if ok and type(v) == "number" then return v end
	return 0
end

--- The temporary damage reduction of Raise Shields, Martyrdom and the Balance rune "Share" (stacking prefix h47Share) only applies to the engine's own hit; damage computed in Lua ignores it
local function isShare(b)
	return string.sub(b:getStacking(), 1, 8) == "h47Share"
end

--- Combined factor of the attacker's damage boost and the target's reduction (added in review A3, 2026-11-08):
---   (100 + attacker GENERAL_DAMAGE_PREMY) x (100 - min(100, target GENERAL_DAMAGE_REDUCTION all + melee or ranged)) / 10000
--- If ranged is true the ranged reduction is used, otherwise the melee one. 0 when reduction reaches 100% (Petrify, Abyssal Gate, Time Jump etc.) or the boost drops to -100% (Siren Song)
function M.damageModifier(attacker, target, ranged)
	local premy = bonusSum(attacker, { type = "GENERAL_DAMAGE_PREMY" })
	local reduction = bonusSum(target, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }, isShare)
		+ bonusSum(target, { type = "GENERAL_DAMAGE_REDUCTION", subtype = ranged and "damageTypeRanged" or "damageTypeMelee" }, isShare)
	return math.max(0, 100 + premy) * (100 - math.min(100, reduction)) / 10000
end

--- Normal attack damage: stack size x random damage x attack/defense modifier (H3 formula) x boost / reduction (M.damageModifier) x pct%. Luck and Morale are not counted.
--- ranged: whether this hit counts as a shot (true) or melee (false / omitted); decides which attack, defense, damage and reduction values are used.
--- Returns 0 when reduction is 100% (L.hit does not subtract 0); otherwise at least 1. The interface is unchanged, old calls still work
function M.attackDamage(server, attacker, target, pct, ranged)
	ranged = ranged == true
	local modifier = M.damageModifier(attacker, target, ranged)
	if modifier <= 0 then return 0 end
	local base = rollBase(server, attacker, ranged)
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * modifier * (pct or 100) / 100))
end

--- Subtract health and play the animation (animation deferred, in the same beat as the damage). Returns actual damage, deaths
function M.hit(server, battle, target, amount, animation, sound)
	if target == nil or not target:isAlive() or target:isGhost() or target:isInvincible() or amount <= 0 then return 0, 0 end
	if animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = target } }, animation, sound or "", 1.0, true)
	end
	return server:damageUnit(battle, target, amount)
end

-- ---- Hidden marks -------------------------------------------------------------------------------

local function markList(unit, key)
	return unit:getBonuses({ type = M.MARK }):filter(function(b) return b:getStacking() == key end)
end

function M.markValue(unit, key)
	local list = markList(unit, key)
	if list:size() == 0 then return nil end
	return list:getBonus(1):getVal()
end

function M.clearMark(server, battle, unit, key)
	local list = markList(unit, key)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

--- turns = nil means the whole battle
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

-- ---- "Already restored" mark (review A5, 2026-11-08) ----------------------------------------------------
--- Convention (shared by heroes-memorial.h6 and heroes-memorial.dynasty-weapons through string conventions only, without depending on each other; the Dynasty Weapons have the same copy in spells/h6dynLib):
---   * Mark: a hidden bonus on the target of type MEMORIAL_MARK, stacking "h6Healed|<attacker stack id>",
---     value = health already restored for this attack, lasting 1 round (as a fallback; normally cleared before the next attack).
---   * Scripts that restore damage after a hit (h6dynShield, h6SpShieldAbsorb, h6SpSacrificeLink, h6Impervious, h6MmFeignHit), in onAfterAttacked
---     only handle entry.damage minus what is already restored, then add the amount they restored (or transferred, or booked as debt) to the mark, so together they restore at most one share of the same hit.
---   * Their onBeforeAttacked all call clearHealed to clear every "h6Healed|" mark on the target (triggered before every attack, counterattack and second strike),
---     so a mark is only valid within the "after being hit" triggers of the same attack.
---   * Spell damage (onSpellHit) does not use the mark: each script works from the difference between unitBefore and the current health, so what earlier scripts restored is already deducted.
M.HEALED = "h6Healed|"

local function healedKey(other)
	return M.HEALED .. tostring(other and other:unitID() or -1)
end

local function isHealedMark(b)
	return string.sub(b:getStacking(), 1, #M.HEALED) == M.HEALED
end

--- Amount already restored for this hit (attacker other)
function M.healedValue(unit, other)
	local key = healedKey(other)
	local list = unit:getBonuses({ type = "MEMORIAL_MARK" }):filter(function(b) return b:getStacking() == key end)
	local v = 0
	for i = 1, list:size() do v = v + list:getBonus(i):getVal() end
	return v
end

--- Amount not yet restored for this hit (entry.damage minus what is restored)
function M.unhealed(unit, other, damage)
	return math.max(0, (damage or 0) - M.healedValue(unit, other))
end

--- Record the amount restored this time (added to the mark)
function M.addHealed(server, battle, unit, other, amount)
	if amount == nil or amount <= 0 then return end
	local key = healedKey(other)
	local total = M.healedValue(unit, other) + amount
	local list = unit:getBonuses({ type = "MEMORIAL_MARK" }):filter(function(b) return b:getStacking() == key end)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
	server:addUnitBonus(battle, unit, {
		type       = "MEMORIAL_MARK",
		val        = total,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		stacking   = key,
		hidden     = true
	}, true)
end

--- Clear every "already restored" mark on the target (called in onBeforeAttacked)
function M.clearHealed(server, battle, unit)
	local list = unit:getBonuses({ type = "MEMORIAL_MARK" }):filter(isHealedMark)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

-- ---- Bonuses -----------------------------------------------------------------------------------

function M.addBonus(server, battle, unit, desc, cumulative)
	desc.sourceType = desc.sourceType or ENUM.BonusSource.creatureAbility
	desc.sourceID = desc.sourceID or unit:getCreature():getJsonKey()
	desc.valueType = desc.valueType or ENUM.BonusValueType.additiveValue
	if desc.duration == nil then desc.duration = ENUM.BonusDuration.oneBattle end
	server:addUnitBonus(battle, unit, desc, cumulative ~= false)
end

function M.removeByStacking(server, battle, unit, typeName, stacking)
	local list = unit:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == stacking end)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

-- ---- Casts -------------------------------------------------------------------------------

--- Record one use; if maxUses is nil (unlimited) or not used up yet, refund this cast (CASTS +1, whole battle).
--- VCMI casts are shared by all spells of a stack, so "unlimited / N per battle" is done by refunding
function M.useCast(server, battle, caster, key, maxUses)
	if caster == nil then return end
	local used = (M.markValue(caster, key) or 0) + 1
	M.setMark(server, battle, caster, key, used)
	if maxUses == nil or used < maxUses then
		server:addUnitBonus(battle, caster, {
			type       = "CASTS",
			val        = 1,
			valueType  = ENUM.BonusValueType.additiveValue,
			duration   = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.creatureAbility,
			sourceID   = caster:getCreature():getJsonKey(),
			hidden     = true
		}, true)
	end
end

-- ---- Battle log -------------------------------------------------------------------------------

function M.name(unit)
	return unit:getCreature():getNameTextID(unit:getCount())
end

--- Write one battle log line: core.bonus.<mark>.description.<index>
-- These marks show in the stack's ability panel, so battle log text indexes get +900000, otherwise an ability value equal to an index would show as a log template
local LOG_OFFSET_MARKS = { H6_CHARMED_H6C = true, H6_DEATH_SEAL_H6C = true, H6_DEVOURED_H6C = true, H6_DOOM_H6C = true, H6_DOT_H6C = true, H6_ENRAGED_H6C = true, H6_IMPERVIOUS_H6C = true, H6_LIFE_DRAIN_H6C = true, H6_PUTRESCENCE_H6C = true, H6_SUN_STEED_H6C = true, H6_TAUNT_H6C = true, H6_TERRIFIED_H6C = true, H6_VIGILANT_H6C = true, H6_VOIDGATE_H6C = true, H6_WITHER_H6C = true }

function M.log(server, battle, mark, index, strings, numbers)
	if not server:describeChanges() then return end
	if LOG_OFFSET_MARKS[mark] then index = 900000 + index end
	server:appendLog(battle, {
		append         = { "core.bonus." .. mark .. ".description." .. tostring(index) },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

--- Get the spell object: by full name first, then by short name
function M.spell(name)
	local s = nil
	pcall(function() s = LIBRARY:getSpellByName(name) end)
	if s == nil then pcall(function() s = LIBRARY:getSpellByName(M.MOD .. ":" .. name) end) end
	return s
end

-- ---- Damage over time (poison, worms): hidden bonus H6_DOT_H6C, settled by h6Dot (battle-wide) at the start of each round ----------------------

--- Add damage over time to target: val per round, settled ticks times. An older entry from the same source src is removed first (no stacking, the new one wins)
function M.addDot(server, battle, target, src, val, ticks)
	if target == nil or not target:isAlive() or val <= 0 then return end
	local key = "h6Dot:" .. src
	M.removeByStacking(server, battle, target, "H6_DOT_H6C", key)
	server:addUnitBonus(battle, target, {
		type       = "H6_DOT_H6C",
		val        = val,
		valueType  = ENUM.BonusValueType.additiveValue,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = ticks + 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = target:getCreature():getJsonKey(),
		stacking   = key
	}, true)
end

--- Adjacent stacks, counted only if filter(u) is true
function M.around(battle, unit, filter)
	local out = {}
	local list = battle:getUnitsIf(function(u) return M.real(u) and u:unitID() ~= unit:unitID() and M.adjacent(unit, u) end)
	for _, u in ipairs(list) do
		if filter == nil or filter(u) then out[#out + 1] = u end
	end
	return out
end

--- Spell damage scaled by school reduction (all spells + the given school, at most 100%)
function M.schoolReduction(u, school)
	local r = u:getBonusesValue({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any" })
	if school then
		local ok, l = pcall(function() return u:getBonusesValue({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool." .. school }) end)
		if ok and l then r = r + l end
	end
	return math.max(-100, math.min(r, 100))
end

--- Animation (deferred) + refresh, for effects that do no damage
function M.show(server, battle, units, animation, sound)
	if animation == nil or not server:describeChanges() then return end
	local t = {}
	for _, u in ipairs(units) do t[#t + 1] = { unit = u } end
	if #t == 0 then return end
	server:showBattleAnimation(battle, t, animation, sound or "", 1.0, true)
	server:refreshBattleUnits(battle)
end

-- ---- Helpers for the boss batch (round 352) -------------------------------------------------------------

--- Push the single-hex stack u up to dist hexes away along the direction "hex nearest to from -> u" (stops at the previous hex if blocked). Returns whether it moved
function M.knock(server, battle, from, u, dist)
	if not u:isAlive() or u:getHexes():size() ~= 1 then return false end
	local a, b = from:getPosition(), u:getPosition()
	local bd = 1000
	local ch = from:getHexes()
	for i = 1, ch:size() do
		local d = M.hexDistance(ch:at(i), b)
		if d < bd then a, bd = ch:at(i), d end
	end
	local hexes = M.hexTable(battle)
	local dest = nil
	for k = 1, (dist or 1) do
		local idx = M.lineIndex(a, b, bd + k)
		local h = idx and hexes[idx]
		if h and h:isAvailable() and battle:isAccessibleForUnit(u, h) then dest = h else break end
	end
	if dest then server:moveUnit(battle, u, dest, true); return true end
	return false
end

--- Subtract health directly, ignoring invincibility and invisibility (damage settled "inside", like being devoured or the Void Gate). Returns actual damage, deaths
function M.rawHit(server, battle, target, amount, animation, sound)
	if target == nil or not target:isAlive() or amount <= 0 then return 0, 0 end
	if animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = target } }, animation, sound or "", 1.0, true)
	end
	return server:damageUnit(battle, target, amount)
end

--- Stacks of the same side and the given creatures (ids is {full creature name = true}); alive = true for living ones only
function M.friendsOfType(battle, side, ids, alive)
	return battle:getUnitsIf(function(u)
		if u:getSide() ~= side or u:isGhost() then return false end
		if alive and not u:isAlive() then return false end
		return ids[u:getCreature():getJsonKey()] == true
	end)
end

--- Total health of a stack at battle start (initial count x health per creature)
function M.initialHealth(unit)
	return math.max(unit:getBaseAmount(), unit:getCount()) * unit:getMaxHealth()
end

--- With the Ring of Oblivion (new hota artifact, HOTA_RING_OF_OBLIVION) in play there is no resurrection: only the top creature is healed, without overflow (as h5Common.reviveHeal and hota ringOfOblivionPatch.lua, merged in round 418).
--- Without the new hota artifacts this bonus type does not exist, so it is looked up with pcall. Returns (heal amount, heal level)
function M.reviveHeal(unit, amount)
	local ok, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	if ok and ring then
		if not unit:isAlive() then return 0, ENUM.HealLevel.heal end
		return math.min(amount, unit:getMaxHealth() - unit:getFirstHPleft()), ENUM.HealLevel.heal
	end
	return amount, ENUM.HealLevel.resurrect
end

--- Divination (changechanceskill): the hero's Divination raises the chance of chance-based creature abilities by 20% / 50% / 100% through the hidden bonus CHANGECHANCE_BOOST (value = increase in percent).
--- Without the Divination mod the type cannot be found and counts as 0 (as h5Common.boost, merged in round 418). M.chance(unit, base) = increased chance (at most 100)
function M.boost(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "CHANGECHANCE_BOOST" }) end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 0
end
function M.chance(unit, base) return math.min(100, math.floor(base * (100 + M.boost(unit)) / 100)) end

return M
