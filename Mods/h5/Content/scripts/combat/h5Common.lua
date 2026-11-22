--- H5 Creatures and Magic (heroes-memorial.h5): small helpers shared by the scripts. Only used via require("combat/h5Common"), not registered as a script.
---
--- Functions (M = require("combat/h5Common"))
---   Distance, hexes
---     M.W                              number of hexes in a battlefield row (17)
---     M.hexIndex(hex)                  hex index
---     M.hexDistance(a, b)              distance between two hexes (same as the engine's BattleHex::getDistance)
---     M.unitDistance(a, b)             nearest distance between the hexes of two stacks (adjacent = 1)
---     M.unitHexDistance(u, hex)        nearest distance from a stack to a hex
---     M.hexTable(battle)               hex lookup for the whole field: index -> BattleHex
---     M.lineIndex(a, b, k)             draws a line from a to b and returns the hex index of step k (k may exceed the distance, extending the line; nil when out of bounds)
---     M.pushHex(battle, from, unit, steps)  landing spot (BattleHex) when pushing the stack steps hexes outward along "from -> stack"; nil if it cannot stand there
---     M.hostile(battle, actor, u) / M.isEnemy(u, side) / M.isRealStack(u)  friend or foe, real stack (alive, not a ghost, arrow tower or war machine)
---     M.adjacentUnits(battle, unit, pred)    stacks adjacent to unit (pred optional)
---   Chance
---     M.boost(unit)                    percent increase from Deduction (CHANGECHANCE_BOOST, 0 if not installed)
---     M.procChance(attacker, defender, pf, defenderHealth)  chance of H5 probability-based abilities (percent, integer)
---                                      ratio = attacker total health / defender total health (the defender's current total health if defenderHealth is not given)
---                                      base = 0.25 +/- 0.03 x health ratio, limited to [0.05,0.75]; P = 1-(1-base)^pf; then x (100 + Deduction)/100, capped at 100
---     M.roll(server, battle, actor, pct) roll a chance (rollCombatAbility, falling back to rngInt)
---   Spell power
---     M.growth(unit)                   H5 weekly growth (hidden bonus H5_GROWTH_H5C on the creature, otherwise the engine's growth)
---     M.creatureSP(unit)               spell power of creature casts: trunc(21 x log10(10 + 10 x count / growth) - 22), at least 1
---   Kinds, immunities
---     M.isUndead / isMechanical / isElemental / isNonLiving / isLivingH5(unit)
---     M.immuneToSpell(unit, spellName, tags)  immunity check by spell and school tags (tags: { mind=true, living=true, school="fire" })
---     M.hasMark(unit, typeName) / M.markVal(unit, typeName)   marks carried by the creature (H5_ARMORED_H5C and such)
---   Hidden marks (H5_MARK_H5C, told apart by stacking group name)
---     M.markValue(unit, key)           read a mark, nil if absent
---     M.setMark(server, battle, unit, key, val, turns)   attach a mark (the old one of the same name removed first); turns = nil for the whole battle
---     M.clearMark(server, battle, unit, key)
---   Turn order (H5 ATB)
---     M.resetAtb(server, battle, unit) initiative reset: a stack that has not acted this round no longer acts (setFear, skipped on its turn, cleared automatically next round); no change if it already acted
---     M.slowNextTurn(server, battle, unit, pct, turns, source)  Speed -pct% (approximation of lowered initiative)
---   Move distance (this stack's own move)
---     M.recordMoveStart(server, battle, unit) / M.recordMoveEnd(server, battle, unit) / M.movedCells(unit)
---   Bonuses
---     M.removeByStacking(server, battle, unit, type, stacking)
---     M.addTemp(server, battle, unit, desc)  adds a bonus from this mod (sourceType = other), desc as BonusDescriptor
---   Battle log
---     M.log(server, battle, textId, strings, numbers)
---   Source creature (copied creatures such as shrunk or downgraded versions)
---     M.sourceKey(unit)                id used for table lookups by creature id (with mod prefix): copied creatures read the hidden bonus H5_SOURCE_H5C
---                                      (stacking "h5Src|<full name of the source creature>"), otherwise its own id
---     M.sourceShortKey(unit)           as above, without the mod prefix

local M = {}
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)

M.W = 17
M.MARK = "H5_MARK_H5C"
M.MOD = "heroes-memorial.h5"

function M.hexIndex(hex)
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

function M.unitDistance(a, b)
	local ha, hb = a:getHexes(), b:getHexes()
	local best = 1000
	for i = 1, ha:size() do
		for j = 1, hb:size() do
			local d = M.hexDistance(ha:at(i), hb:at(j))
			if d < best then best = d end
		end
	end
	return best
end

function M.unitHexDistance(u, hex)
	local hs = u:getHexes()
	local best = 1000
	for i = 1, hs:size() do
		local d = M.hexDistance(hs:at(i), hex)
		if d < best then best = d end
	end
	return best
end

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

--- Push unit steps hexes outward along "from -> unit" and return the landing spot; nil if it cannot stand there (out of bounds, occupied, obstacle)
function M.pushHex(battle, from, unit, steps)
	local pos = unit:getPosition()
	local n = M.hexDistance(from, pos)
	if n == 0 then return nil end
	local hexes = M.hexTable(battle)
	local idx = M.lineIndex(from, pos, n + steps)
	if idx == nil then return nil end
	local dest = hexes[idx]
	if dest == nil then return nil end
	local ok, accessible = pcall(function() return battle:isAccessibleForUnit(unit, dest) end)
	if ok and accessible then return dest end
	return nil
end

function M.isRealStack(u)
	if u == nil or not u:isAlive() or u:isGhost() or u:isTurret() then return false end
	if u:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	return true
end

function M.isEnemy(u, side)
	return u:getSide() ~= side and u:isAlive() and not u:isGhost() and not u:isTurret()
end

--- Enemies as seen by actor (hypnotized stacks count for the controlling side, as newer engines do)
function M.hostile(battle, actor, u)
	return battle:isHostile(actor, u) and u:isAlive() and not u:isGhost() and not u:isTurret()
end

function M.adjacentUnits(battle, unit, pred)
	local list = battle:getUnitsIf(function(o)
		return o:isAlive() and not o:isGhost() and o:unitID() ~= unit:unitID()
	end)
	local out = {}
	for _, o in ipairs(list) do
		if M.unitDistance(unit, o) == 1 and (pred == nil or pred(o)) then
			table.insert(out, o)
		end
	end
	return out
end

-- ---- Chance -----------------------------------------------------------------------------------

function M.boost(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "CHANGECHANCE_BOOST" }) end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 0
end

function M.procChance(attacker, defender, pf, defenderHealth)
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
	local p = (1 - (1 - base) ^ (pf or 1)) * 100
	p = p * (100 + M.boost(attacker)) / 100
	if p > 100 then p = 100 end
	return math.floor(p + 0.5)
end

function M.roll(server, battle, actor, pct)
	if pct >= 100 then return true end
	if pct <= 0 then return false end
	local ok, result = pcall(function() return server:rollCombatAbility(battle, actor, pct) end)
	if ok and type(result) == "boolean" then return result end
	return server:rngInt(1, 100) <= pct
end

-- ---- Spell power -------------------------------------------------------------------------------

function M.growth(unit)
	local g = unit:getBonusesValue({ type = "H5_GROWTH_H5C" })
	if g and g > 0 then return g end
	local ok, eg = pcall(function() return unit:getCreature():getGrowth() end)
	if ok and type(eg) == "number" and eg > 0 then return eg end
	return 1
end

function M.creatureSP(unit)
	local n = math.max(1, unit:getCount())
	local g = M.growth(unit)
	local sp = 21 * math.log(10 + 10 * n / g) / math.log(10) - 22
	sp = math.floor(sp)
	if sp < 1 then sp = 1 end
	return sp
end

-- ---- Kinds, immunities -----------------------------------------------------------------------------

function M.isUndead(u) return u:hasBonuses({ type = "UNDEAD" }) end
function M.isMechanical(u) return u:hasBonuses({ type = "MECHANICAL" }) end
function M.isNonLiving(u) return u:hasBonuses({ type = "NON_LIVING" }) end
function M.isElemental(u)
	return u:hasBonuses({ type = "H5_ELEMENTAL_H5C" }) or u:hasBonuses({ type = "NON_LIVING" })
end
--- "Living" in the H5 sense: not undead, elemental, mechanical or a war machine
function M.isLivingH5(u)
	return not (M.isUndead(u) or M.isMechanical(u) or M.isNonLiving(u) or u:hasBonuses({ type = "SIEGE_WEAPON" }))
end

function M.hasMark(unit, typeName) return unit:hasBonuses({ type = typeName }) end
function M.markVal(unit, typeName) return unit:getBonusesValue({ type = typeName }) end

--- tags: mind = mind spells; living = living targets only; school = "fire"/"water"/"air"/"earth"
function M.immuneToSpell(unit, spellName, tags)
	tags = tags or {}
	if unit:isInvincible() then return true end
	if spellName and spellName ~= "" then
		local short = string.gsub(spellName, "^.*:", "")
		if unit:hasBonuses({ type = "SPELL_IMMUNITY", subtype = short }) then return true end
		local ok, r = pcall(function() return unit:hasBonuses({ type = "SPELL_IMMUNITY", subtype = M.MOD .. ":" .. short }) end)
		if ok and r then return true end
	end
	if unit:getBonusesValue({ type = "LEVEL_SPELL_IMMUNITY" }) >= 5 then return true end
	if tags.mind and unit:hasBonuses({ type = "MIND_IMMUNITY" }) then return true end
	if tags.living and not M.isLivingH5(unit) then return true end
	if tags.school then
		if unit:hasBonuses({ type = "SPELL_SCHOOL_IMMUNITY", subtype = tags.school }) then return true end
		if unit:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = tags.school }) then return true end
	end
	if tags.negative and unit:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "any" }) then return true end
	return false
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
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

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

-- ---- Bonuses -----------------------------------------------------------------------------------

function M.removeByStacking(server, battle, unit, typeName, stacking)
	local list = unit:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == stacking end)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function M.addTemp(server, battle, unit, desc, cumulative)
	desc.sourceType = desc.sourceType or ENUM.BonusSource.other
	desc.sourceID = desc.sourceID or unit:getCreature():getJsonKey()
	if desc.duration == nil then desc.duration = ENUM.BonusDuration.oneBattle end
	server:addUnitBonus(battle, unit, desc, cumulative == true)
end

-- ---- Turn order -------------------------------------------------------------------------------

function M.resetAtb(server, battle, unit)
	if not unit:isAlive() then return end
	local state = unit:copy()
	state:setFear(true) -- Newer engines removed setMoved; after the PR was merged setTurnStatus(ENUM.UnitTurnStatus.acted) is used
	server:changeUnit(battle, state, 0)
end

function M.slowNextTurn(server, battle, unit, pct, turns, source, stacking)
	M.removeByStacking(server, battle, unit, "STACKS_SPEED", stacking or "h5AtbDrop")
	server:addUnitBonus(battle, unit, {
		type       = "STACKS_SPEED",
		val        = -pct,
		valueType  = ENUM.BonusValueType.percentToAll,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = turns or 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = source,
		stacking   = stacking or "h5AtbDrop",
		hidden     = true
	}, true)
end

-- ---- Move distance -------------------------------------------------------------------------------

function M.recordMoveStart(server, battle, unit)
	M.setMark(server, battle, unit, "h5MoveFrom", M.hexIndex(unit:getPosition()), 1)
end

function M.recordMoveEnd(server, battle, unit)
	local from = M.markValue(unit, "h5MoveFrom")
	if from == nil then return end
	local hexes = M.hexTable(battle)
	local start = hexes[from]
	local cells = 0
	if start ~= nil then cells = M.hexDistance(start, unit:getPosition()) end
	M.setMark(server, battle, unit, "h5Moved", cells, 1)
end

--- How many hexes it moved in this action (0 if it did not move)
function M.movedCells(unit)
	return M.markValue(unit, "h5Moved") or 0
end

function M.clearMove(server, battle, unit)
	M.clearMark(server, battle, unit, "h5Moved")
	M.clearMark(server, battle, unit, "h5MoveFrom")
end

-- ---- Battle log -------------------------------------------------------------------------------

function M.log(server, battle, textId, strings, numbers)
	server:appendLog(battle, {
		append         = { textId },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

function M.name(unit)
	return unit:getCreature():getNameTextID(unit:getCount())
end

--- Source creature. Shrunk versions, downgraded forms and downgraded shrunk forms made by other mods have separate ids,
--- and their generator script gives them the hidden bonus H5_SOURCE_H5C, stacking "h5Src|heroes-memorial.h5:<source creature>"
--- (a shrunk version is the original creature, a downgraded form the creature one tier lower). Tables looked up by id (Blood Rage data, goblin/treant lists) read this mark first.
local SOURCE_PREFIX = "h5Src|"

function M.sourceKey(unit)
	local ok, list = pcall(function() return unit:getBonuses({ type = "H5_SOURCE_H5C" }) end)
	if ok and list ~= nil then
		for i = 1, list:size() do
			local st = list:getBonus(i):getStacking()
			if string.sub(st, 1, #SOURCE_PREFIX) == SOURCE_PREFIX then return string.sub(st, #SOURCE_PREFIX + 1) end
		end
	end
	return unit:getCreature():getJsonKey()
end

function M.sourceShortKey(unit)
	local k = M.sourceKey(unit)
	return k:match(":(.+)$") or k
end

--- The entry for unit in the attack record (payload.targets), and the first stack hit
function M.firstTarget(payload)
	for _, t in ipairs((payload and payload.targets) or {}) do
		if t.unit then return t end
	end
	return nil
end

--- Get the spell object: by full name first, then by short name
function M.spell(name)
	local s = nil
	pcall(function() s = LIBRARY:getSpellByName(M.MOD .. ":" .. name) end)
	if s == nil then pcall(function() s = LIBRARY:getSpellByName(name) end) end
	return s
end

--- With the Ring of Oblivion (new hota artifact, HOTA_RING_OF_OBLIVION) in play, resurrection is not possible: only the top creature's health is restored, no overflow (as hota ringOfOblivionPatch.lua).
--- Without the new hota artifacts this bonus type does not exist, so it is looked up with pcall. Returns (heal amount, heal level)
function M.reviveHeal(unit, amount)
	local ok, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	if ok and ring then
		if not unit:isAlive() then return 0, ENUM.HealLevel.heal end
		return math.min(amount, unit:getMaxHealth() - unit:getFirstHPleft()), ENUM.HealLevel.heal
	end
	return amount, ENUM.HealLevel.resurrect
end

return M
