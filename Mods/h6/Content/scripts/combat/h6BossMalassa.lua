local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Daughter of Malassa (H6 boss):
---   role = "carrier": Weariness: enemies attacking her in melee deal -pct% damage for 2 rounds, stacking up to 2 layers, cannot be dispelled;
---   role = "zone" (battle-wide): when a stack with the Mark of Doom (H6_DOOM_H6C) receives a beneficial spell, that spell is cancelled at once.
--- Parameters: role, pct, animation, sound

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if self.role == "zone" then return end
	if other == nil or not other:isAlive() or payload.ranged or payload.isCounter or not battle:isHostile(unit, other) then return end
	local src = unit:getCreature():getJsonKey()
	local key = "h6Weary1"
	if other:getBonuses({ type = "GENERAL_DAMAGE_PREMY" }):filter(function(b) return b:getStacking() == "h6Weary1" end):size() > 0 then key = "h6Weary2" end
	L.removeByStacking(server, battle, other, "GENERAL_DAMAGE_PREMY", key)
	server:addUnitBonus(battle, other, { type = "GENERAL_DAMAGE_PREMY", val = -(self.pct or 40), duration = ENUM.BonusDuration.nTurns, turns = 2,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = key }, true)
	L.removeByStacking(server, battle, other, "H6_WEARY_H6C", key)
	server:addUnitBonus(battle, other, { type = "H6_WEARY_H6C", val = self.pct or 40, duration = ENUM.BonusDuration.nTurns, turns = 2,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = key }, true)
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if self.role ~= "zone" or not unit:isAlive() or not unit:hasBonuses({ type = "H6_DOOM_H6C" }) then return end
	local sp = payload and payload.spell
	if sp == nil or not sp:isPositive() then return end
	local key = sp:getJsonKey()
	local list = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b) return b:getSourceID() == key end)
	if list:size() > 0 then
		server:removeUnitBonuses(battle, unit, list)
		L.log(server, battle, "H6_DOOM_H6C", 1, { L.name(unit) }, {})
	end
end

return Script
