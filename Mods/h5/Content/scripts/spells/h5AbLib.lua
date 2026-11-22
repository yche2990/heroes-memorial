--- H5 Creatures and Magic (heroes-memorial.h5): small helpers shared by creature active abilities (spell effect scripts).
--- Only used via require("spells/h5AbLib"), not registered as a script. General tools such as distance, marks and chance are in combat/h5Common; only active-ability-specific ones are here.
---
---   L.C                                  combat/h5Common
---   L.A                                  combat/h5Area (normal attack damage attackDamage, hit)
---   L.caster(mechanics)                  casting stack (nil when a hero casts)
---   L.sp(unit)                           spell power of creature casts (H5 formula)
---   L.useCast(server, battle, caster, key, maxUses)
---                                      Record one use; if maxUses is nil (unlimited) or not used up yet, refund this cast (CASTS +1, whole battle).
---                                      These H5 active abilities cost no mana, while VCMI's casts are shared by all spells, so "unlimited / N per battle" is done by refunding
---   L.usedCount(unit, key)               how many times used
---   L.isGoblin(unit)                     H5 goblins (three kinds) and the original Goblin, Hobgoblin
---   L.isTreant(unit)                     H5 treants (three kinds)
---   L.adjacent(a, b)                     whether two stacks are adjacent
---   L.addBonus(server, battle, unit, desc, cumulative)   bonus with creature ability source (sourceType = creatureAbility)
---   L.log(server, battle, mark, index, strings, numbers) writes a battle log line (core.bonus.<mark>.description.<index>)
---   L.encoded(level, sp)                 effect value when casting h5 spells (group A) with server:castSpell: 1000000 + level*100000 + SP

local C = require("combat/h5Common")
local A = require("combat/h5Area")

local L = {}
L.C = C
L.A = A
L.MOD = "heroes-memorial.h5"

function L.caster(mechanics)
	return mechanics:getUnitCaster()
end

function L.sp(unit)
	return C.creatureSP(unit)
end

function L.usedCount(unit, key)
	return C.markValue(unit, key) or 0
end

function L.useCast(server, battle, caster, key, maxUses)
	if caster == nil then return end
	local used = L.usedCount(caster, key) + 1
	C.setMark(server, battle, caster, key, used)
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

local GOBLINS = {
	["h5OrcsGoblin1"] = true, ["h5OrcsGoblin2"] = true, ["h5Orcs3rdGoblinDefiler"] = true,
	["goblin"] = true, ["hobgoblin"] = true
}
local TREANTS = { ["h5PreserveTreant"] = true, ["h5PreserveTreantGuardian"] = true, ["h5Preserve3rdAngerTreant"] = true }

local function short(key)
	return key:match(":(.+)$") or key
end

--- Shrunk and downgraded copies are counted by source creature (h5Common.sourceKey)
function L.isGoblin(unit)
	return GOBLINS[short(C.sourceKey(unit))] == true
end

function L.isTreant(unit)
	return TREANTS[short(C.sourceKey(unit))] == true
end

function L.adjacent(a, b)
	local around = a:getSurroundingHexes()
	local hexes = b:getHexes()
	for i = 1, hexes:size() do
		if around:contains(hexes:at(i)) then return true end
	end
	return false
end

function L.addBonus(server, battle, unit, desc, cumulative)
	desc.sourceType = desc.sourceType or ENUM.BonusSource.creatureAbility
	desc.sourceID = desc.sourceID or unit:getCreature():getJsonKey()
	desc.valueType = desc.valueType or ENUM.BonusValueType.additiveValue
	if desc.duration == nil then desc.duration = ENUM.BonusDuration.oneBattle end
	server:addUnitBonus(battle, unit, desc, cumulative ~= false)
end

function L.log(server, battle, mark, index, strings, numbers)
	server:appendLog(battle, {
		append         = { "core.bonus." .. mark .. ".description." .. tostring(index) },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

function L.encoded(level, sp)
	return 1000000 + level * 100000 + math.max(0, sp)
end

--- Whether it is a real stack (alive, on the field, not an arrow tower or war machine)
function L.real(u)
	return C.isRealStack(u)
end

--- Whether something other than this side blocks it: no living stack on the hex
function L.hexFree(battle, hex)
	if hex == nil or not hex:isValid() or not hex:isAvailable() then return false end
	return battle:getUnitByPos(hex, true) == nil
end

--- The free hex nearest to hex where unit can stand (may be hex itself)
function L.nearestFree(battle, unit, hex)
	local hexes = C.hexTable(battle)
	local best, bestD = nil, 1000
	for _, h in pairs(hexes) do
		if h:isAvailable() and battle:isAccessibleForUnit(unit, h) then
			local d = C.hexDistance(h, hex)
			if d < bestD then best, bestD = h, d end
		end
	end
	return best
end

--- Of the free hexes adjacent to target where unit can stand, the one nearest to from
function L.freeHexNextTo(battle, unit, target, from)
	local around = target:getSurroundingHexes()
	local best, bestD = nil, 1000
	for i = 1, around:size() do
		local h = around:at(i)
		if h:isValid() and h:isAvailable() and battle:isAccessibleForUnit(unit, h) then
			-- A two-hex stack standing on this hex must also be adjacent to target
			local d = from and C.hexDistance(h, from) or 0
			if d < bestD then best, bestD = h, d end
		end
	end
	return best
end

--- Whether the battle can go on (the other side still has stacks)
function L.enemiesLeft(battle, side)
	local list = battle:getUnitsIf(function(u)
		return u:getSide() ~= side and u:isAlive() and not u:isGhost() and not u:isTurret()
	end)
	return #list > 0
end

return L
