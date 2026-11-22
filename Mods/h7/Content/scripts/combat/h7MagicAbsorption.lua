local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Magic Absorption (Colossus, Titan, Shantiri Titan)
---
--- When it takes spell damage (spells actively cast by heroes and stacks; obstacles, spell-like attacks and script casts are not reported by the engine), the health lost is recorded
--- and added to this stack's next attack (ranged, melee or counterattack): after hitting, the target takes that much extra Prime damage (only the "all magic" reduction applies;
--- stacks immune to all schools take none). Cumulative cap = current count x maximum damage. Reset after one extra hit.
--- Display: H7_MAGIC_ABSORB_H7C (value = damage currently stored).

local KEY = "h7MagicAbsorb"
local SHOW = "H7_MAGIC_ABSORB_H7C"

local function stored(unit)
	local list = L.byStacking(unit, SHOW, KEY)
	if list:size() == 0 then return 0 end
	return list:getBonus(1):getVal()
end

local function cap(unit)
	return math.max(1, unit:getCount() * math.max(1, unit:getMaxDamage(false)))
end

local function setStored(server, battle, unit, v)
	L.removeByStacking(server, battle, unit, SHOW, KEY)
	if v <= 0 then return end
	server:addUnitBonus(battle, unit, {
		type = SHOW, val = v, stacking = KEY, icon = "h7/abilities/h7MagicAbsorption",
		duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
	}, false)
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil then return end
	local dmg = entry.damage or 0
	if dmg <= 0 then return end
	local v = math.min(stored(unit) + dmg, cap(unit))
	setStored(server, battle, unit, v)
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7MagicAbsorption", "", 1.0, true)
	server:refreshBattleUnits(battle)
	L.log(server, battle, 11, { L.name(unit) }, { dmg })
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local v = stored(unit)
	if v <= 0 then return end
	local main = payload.targets and payload.targets[1]
	if main == nil or main.unit == nil or (main.damage or 0) <= 0 then return end
	local t = main.unit
	if not L.damageable(t) then return end
	setStored(server, battle, unit, 0)
	local dmg = L.schoolDamage(t, math.min(v, cap(unit)), "prime")
	if dmg <= 0 then return end
	local dealt, killed = L.hit(server, battle, t, dmg, "h7/fx/h7PrimeImpact", "")
	L.log(server, battle, 7, { L.name(unit) }, { dealt })
	L.perish(server, battle, t, killed)
end

return Script
