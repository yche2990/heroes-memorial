local Base = require("combat/combatScript")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Whitebear Rider: Bear Roar
---
--- After its own active melee attack, a chance is rolled for the target and each adjacent enemy (ProcFactor = pf, times smallMult for small creatures),
--- those that succeed are frightened: original initiative bar push back 1.0 (done here as: a stack that has not acted this round cannot act this round). Mind-immune stacks and war machines are unaffected.
--- If at least one is frightened, it gets Morale +morale and max health +health% for turns rounds.
---
--- Parameters: pf, smallMult, turns, morale, health

local TARGET_ANIM = "h5/fx/Characters_Fear"   -- Original BearRoar.(SpellVisual), only on frightened stacks
local SOUND = "BLOODLUS"

local function canFear(u)
	return L.isRealUnit(u) and not u:isInvincible() and not u:hasBonuses({ type = "MIND_IMMUNITY" })
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or payload.ranged or payload.isCounter or (payload.attackIndex or 0) > 0 then return end
	local first = payload.targets and payload.targets[1] and payload.targets[1].unit
	if first == nil then return end
	local side = unit:getSide()

	local candidates = { }
	if first:isAlive() and battle:isHostile(unit, first) then table.insert(candidates, first) end
	local around = battle:getUnitsIf(function(u)
		return u:isAlive() and battle:isHostile(unit, u) and u:unitID() ~= first:unitID() and L.adjacent(u, first)
	end)
	for _, u in ipairs(around) do table.insert(candidates, u) end

	local scared = {}
	for _, t in ipairs(candidates) do
		if canFear(t) then
			local pf = self.pf or 0.9
			if not t:getCreature():isDoubleWide() then pf = pf * (self.smallMult or 2) end
			if server:rollCombatAbility(battle, unit, L.procChance(unit, t, pf)) then
				table.insert(scared, t)
			end
		end
	end
	if #scared == 0 then return end

	local dests = {}
	for _, t in ipairs(scared) do table.insert(dests, { unit = t }) end
	server:showBattleAnimation(battle, dests, TARGET_ANIM, SOUND, 0.8, true)
	for _, t in ipairs(scared) do
		L.delayTurn(server, battle, t)
		L.rageEvent(server, battle, t, -100)
		server:appendLog(battle, {
			append = { "core.bonus.H5_BEAR_ROAR_H5C.description.1" },
			replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()), t:getCreature():getNameTextID(t:getCount()) }
		})
	end

	local src = unit:getCreature():getJsonKey()
	local turns = self.turns or 2
	server:addUnitBonus(battle, unit, {
		type = "MORALE", val = self.morale or 1,
		duration = ENUM.BonusDuration.nTurns, turns = turns,
		sourceType = ENUM.BonusSource.creatureAbility, sourceID = src, stacking = "h5BearRoarMorale"
	}, false)
	server:addUnitBonus(battle, unit, {
		type = "STACK_HEALTH", val = self.health or 10, valueType = ENUM.BonusValueType.percentToBase,
		duration = ENUM.BonusDuration.nTurns, turns = turns,
		sourceType = ENUM.BonusSource.creatureAbility, sourceID = src, stacking = "h5BearRoarHealth"
	}, false)
	server:refreshBattleUnits(battle)
end

return Script
