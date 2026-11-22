local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Battle Rage (Battlerager)
--- After taking damage (and surviving), Attack +attack and Initiative +initiative (Speed +initiative x 10%) for turns rounds; further damage only refreshes the rounds, no stacking.
--- Parameters: attack, initiative, turns

local STACK = "h5BattleRage"

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.damage or 0) <= 0 then return end
	local turns = self.turns or 2
	local src = unit:getCreature():getJsonKey()
	local fresh = (H5.markValue(unit, STACK) == nil)
	H5.removeByStacking(server, battle, unit, "PRIMARY_SKILL", STACK)
	H5.removeByStacking(server, battle, unit, "STACKS_SPEED", STACK)
	H5.removeByStacking(server, battle, unit, "H5_BATTLE_RAGE_SHOW_H5C", STACK)
	local function add(d)
		d.duration = ENUM.BonusDuration.nTurns; d.turns = turns
		d.sourceType = ENUM.BonusSource.other; d.sourceID = src; d.stacking = STACK
		server:addUnitBonus(battle, unit, d, false)
	end
	add({ type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = self.attack or 5, hidden = true })
	add({ type = "STACKS_SPEED", val = (self.initiative or 2) * 10, valueType = ENUM.BonusValueType.percentToAll, hidden = true })
	add({ type = "H5_BATTLE_RAGE_SHOW_H5C", val = self.attack or 5 })
	H5.setMark(server, battle, unit, STACK, 1, turns)
	if fresh then
		server:refreshBattleUnits(battle)
		H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.9", { H5.name(unit) }, {})
	end
end

return Script
