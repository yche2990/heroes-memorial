local Base = require("spells/spellEffect")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 warfare units: active abilities usable once per round (round 428; Namtaru's Touch of Darkness, Dream Walker's Shamanic Healing).
--- Written into the same spell as the ability's effects. These two abilities do not end the action (spell canCastWithoutSkip), so the unit can still shoot after casting;
--- this effect allows one cast per round: after casting a 1-round hidden mark is added, which disappears at the start of the next round. Parameter: key (required)

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster ~= nil and W.mark(caster, "h7WfOnce|" .. self.key) ~= nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	W.setMark(server, mechanics:getBattle(), caster, "h7WfOnce|" .. self.key, 1, 1)
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
