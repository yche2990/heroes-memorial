local Base = require("spells/unitEffect")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Clone effect of Phantom Forces (H5): written after the engine's core:clone (scripts/spells/clone.lua), only the source of the clone mark is changed.
--- The engine decides whether a clone is still alive (it vanishes at the start of a round without the mark) only by the NONE mark whose source is the original Clone spell (clone),
--- while core:clone uses the id of the spell cast as the source, so when other spells borrow core:clone the clone vanishes next round.
--- Here the mark source is written as clone, with the duration still from Phantom Forces' own effect.
--- Parameters: maxTier  highest tier that can be cloned

function Script:isReceptive(mechanics, unit)
	if unit:getCreature():getLevel() > self.maxTier then return false end
	return Base.isReceptive(self, mechanics, unit)
end

function Script:isValidTarget(mechanics, unit)
	if unit:isClone()  then return false end
	if unit:hasClone() then return false end
	return unit:isValidTarget(false)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit == nil then goto continue end
		if unit:getCount() < 1 then goto continue end

		local creature = unit:getCreature()
		local hex = battle:getAvailableHex(
			creature,
			mechanics:getCasterSide(),
			unit:getPosition()
		)
		if not hex:isValid() then break end

		local cloneUnit = server:addUnit(battle, {
			count    = unit:getCount(),
			type     = creature,
			side     = mechanics:getCasterSide(),
			position = hex,
			summoned = true
		})
		if cloneUnit == nil then break end

		local cloneState = cloneUnit:copy()
		cloneState:setCloned(true)
		server:changeUnit(battle, cloneState)

		local originalState = unit:copy()
		originalState:setClone(cloneUnit)
		server:changeUnit(battle, originalState)

		server:addUnitBonus(battle, cloneUnit, {
			duration   = ENUM.BonusDuration.nTurns,
			type       = "NONE",
			sourceType = ENUM.BonusSource.spellEffect,
			val        = 0,
			sourceID   = "clone",   -- The engine only accepts marks with this source (BonusCache CLONE_MARKER)
			sourceSecondaryID = mechanics:getEffectLevel(),   -- As in the engine's clone.lua: without it the status description is garbled
			turns      = mechanics:getEffectDuration()
		}, true)

		::continue::
	end
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
