local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Siren Song (H6 Mermaid), hidden battle-wide bonus: an enemy that stops next to a stack carrying H6_SIREN_H6C after moving is charmed by the song
--- and deals -100% damage this round (this hit does no damage). Mind-immune, undead and non-living stacks are not affected. Parameters: animation, sound

function Script:onAfterMove(server, battle, unit)
	if not L.real(unit) or unit:hasBonuses({ type = "MIND_IMMUNITY" }) or not L.isLiving(unit) then return end
	local near = L.around(battle, unit, function(u) return battle:isHostile(unit, u) and u:hasBonuses({ type = "H6_SIREN_H6C" }) end)
	if #near == 0 or unit:hasBonuses({ type = "H6_CHARMED_H6C" }) then return end
	local src = near[1]:getCreature():getJsonKey()
	server:addUnitBonus(battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = -100, duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Siren", hidden = true }, true)
	server:addUnitBonus(battle, unit, { type = "H6_CHARMED_H6C", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Siren" }, true)
	L.log(server, battle, "H6_CHARMED_H6C", 1, { L.name(unit) }, {})
	L.show(server, battle, { unit }, self.animation, self.sound)
end

return Script
