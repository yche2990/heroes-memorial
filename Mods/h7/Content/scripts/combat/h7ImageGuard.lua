local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shadow Image (H7) Expert (with Dark Understanding III): the image's "Shadow Cloak" makes it survive the first attack within 3 rounds.
--- The engine makes a clone vanish on any damage (CUnitState::damage), so before the hit it is temporarily turned into a normal stack with full reduction,
--- and after the hit the damage is restored, it is turned back into a clone and this effect is removed (blocks only once). Spell damage cannot be blocked (the engine has no event before a spell hits).

local REDUCTION = "GENERAL_DAMAGE_REDUCTION"
local ALL = "damageTypeAll"
local TAG = "h7ImageGuard"
local ANIM = "h7/fx/slShadowCloakHit"
local SOUND = "h7/spell_shadow_cloak_tick.ogg"

local function own(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(function(b)
		return b:getStacking() == TAG
	end)
end

local function triggers(unit)
	return unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b)
		return string.find(tostring(b:getSubtype() or ""), TAG, 1, true) ~= nil
	end)
end

local function fullReduction(unit)
	local others = unit:getBonuses({ type = REDUCTION, subtype = ALL }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and b:getStacking() ~= TAG
	end):totalValue()
	return 100 + math.max(0, -others)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() or not unit:isClone() then return end
	if own(unit):size() > 0 then return end
	local st = unit:copy()
	st:setCloned(false)
	server:changeUnit(battle, st)
	server:addUnitBonus(battle, unit, {
		type = REDUCTION, subtype = ALL, val = fullReduction(unit),
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = TAG, hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local red = own(unit)
	if red:size() == 0 then return end
	Proxy.removeExact(server, battle, unit, red)
	if unit:isAlive() then
		local entry = self:ownEntry(unit, payload)
		local damage = entry and entry.damage or 0
		if damage > 0 then
			server:healUnit(battle, unit, damage, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
		end
	end
	local st = unit:copy()
	st:setCloned(true)
	server:changeUnit(battle, st)
	local list = triggers(unit)
	if list:size() > 0 then server:removeUnitBonuses(battle, unit, list) end
	if unit:isAlive() then
		server:showBattleAnimation(battle, { { unit = unit } }, ANIM, SOUND, 0.85, true) server:refreshBattleUnits(battle)
		server:appendLog(battle, {
			append         = { "core.bonus.H7_SL_LOG_H7C.description.6" },
			replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }
		})
	end
end

return Script
