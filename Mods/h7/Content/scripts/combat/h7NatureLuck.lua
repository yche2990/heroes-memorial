local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7AttackLib")
local M = require("heroes-memorial.h7:combat/h7SanctumLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Memorial Sanctum, Nature's Luck (Sylvan ultimate Nature's Luck; a permanent bonus on the hero, passed to the whole army).
--- Original: attacks on enemies with 3 layers of "Avenger's Mark" are always critical. The pack has no mark system, so Yu decided: each time your side attacks an enemy stack it is counted once
--- (stored on the enemy, kept per attacking side, whole battle); enemies your side has attacked at least twice suffer a certain lucky strike from your next attacks (from the 3rd on).
--- The engine rolls lucky strikes with dice, which Lua cannot change, so it is approximated as H5 Nature's Luck: during this attack NO_LUCK
--- (no Luck or bad luck roll) + damage +100% (= lucky strike damage), removed after the attack. Counterattacks and shots count; only the main target.

local STACK = "h7NatureLuck"

--- Mark ids: times attacked by the left side (0) 6, by the right side (1) 7
local function key(side)
	return 6 + side
end

local function clear(server, battle, unit)
	L.removeByStacking(server, battle, unit, "NO_LUCK", STACK)
	L.removeByStacking(server, battle, unit, "PERCENTAGE_DAMAGE_BOOST", STACK)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	clear(server, battle, unit)
	if other == nil or not unit:isAlive() then return end
	if (M.get(other, key(unit:getSide())) or 0) < 2 then return end
	local d = { duration = ENUM.BonusDuration.nTurns, turns = 1, sourceType = ENUM.BonusSource.other,
		sourceID = unit:getCreature():getJsonKey(), stacking = STACK, hidden = true }
	local function add(t, sub, val)
		local x = {}
		for k, v in pairs(d) do x[k] = v end
		x.type, x.subtype, x.val = t, sub, val
		server:addUnitBonus(battle, unit, x, true)
	end
	add("NO_LUCK", nil, 0)
	add("PERCENTAGE_DAMAGE_BOOST", "damageTypeMelee", 100)
	add("PERCENTAGE_DAMAGE_BOOST", "damageTypeRanged", 100)
	server:showBattleAnimation(battle, { { unit = unit } }, "C09SPA0", "GOODLUCK", 1.0, true)
	server:appendLog(battle, {
		append = { "core.bonus.H7_SANCTUM_H7C.description.5" },
		replaceStrings = { L.name(unit), L.name(other) },
		replaceNumbers = {}
	})
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	clear(server, battle, unit)
	if other == nil then return end
	local k = key(unit:getSide())
	M.set(server, battle, other, k, (M.get(other, k) or 0) + 1, nil)
end

return Script
