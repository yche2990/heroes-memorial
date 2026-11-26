local Base = require("spells/spellEffect")
local L = require("spells/h5AbLib")
local C = L.C
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Howl (H5 Wolf): once per battle, summons a stack of the same creature with the same count (summoned, vanishes after battle), on the free hex nearest to itself.
--- In the original the newly summoned wolves start with at most 0.5 initiative (HowlMaxATBValueAtStart): here they do not act this round.
--- Parameters: uses (default 1), mark

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or caster:copy():isSummoned() or caster:isClone() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local creature = caster:getCreature()
	local hex = battle:getAvailableHex(creature, caster:getSide(), caster:getPosition())
	if hex ~= nil and hex:isValid() then
		local unit = server:addUnit(battle, {
			count    = caster:getCount(),
			type     = creature,
			side     = caster:getSide(),
			position = hex,
			summoned = true
		})
		if unit ~= nil then
			local ok = pcall(function()
				local state = unit:copy()
				state:setFear(true) -- No more action this round (newer engines removed setMoved)
				server:changeUnit(battle, state)
			end)
		end
		if server:describeChanges() then
			-- The howl's visual is the spell's own H5 effect (Characters_Fear); the borrowed H3 summon animation is no longer added (audit B III-1)
			server:refreshBattleUnits(battle)
			if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster) }, { caster:getCount() }) end
		end
	end
	L.useCast(server, battle, caster, "h5AbSummonSame", self.uses or 1)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
