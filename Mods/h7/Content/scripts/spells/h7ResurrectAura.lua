local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local C = require("heroes-memorial:combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Second effect of Resurrection (H7), "Elrath's Touch": allies adjacent to the main target (not the main target; undead, non-living, mechanical stacks and war machines excluded)
--- regain amount[mastery] health at once (can resurrect) and get h7ElrathTouch, restoring the same amount at the start of each of the next 2 rounds (3 times in all).
--- This effect is marked optional in the spell json (castable even with no ally next to the main target).
---
--- Parameters:
---   amount    4 numbers, amount restored each time (fixed H7 values, not scaled by Spell Power)
---   turns     rounds (including the round of casting)
---   exclude   bonus types not affected
---   icon      icon for display

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) then return false end
	return Lib.passesFilter(unit, nil, self.exclude)
end

function Script:isReceptive(mechanics, unit)
	return not unit:hasAbsoluteImmunity(mechanics:getSpell())
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local battle = mechanics:getBattle()
	local main = nil
	local d = spellTarget[1] or aimPoint[1]
	if d == nil then return {} end
	if d.unit then main = d.unit
	elseif d.hex and d.hex:isValid() then main = battle:getUnitByPos(d.hex, false) end
	if main == nil then return {} end
	local around = main:getSurroundingHexes()
	local side = mechanics:getCasterSide()
	local mainId = main:unitID()
	local list = battle:getUnitsIf(function(u)
		if u:unitID() == mainId or u:getSide() ~= side then return false end
		if not self:isValidTarget(mechanics, u) then return false end
		local hexes = u:getHexes()
		for i = 1, hexes:size() do
			if around:contains(hexes:at(i)) then return true end
		end
		return false
	end)
	local result = {}
	for _, u in ipairs(list) do result[#result + 1] = { unit = u, hex = u:getPosition() } end
	return result
end

function Script:applicableTarget(mechanics, problem, target)
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local lvl = Lib.level(mechanics)
	local amount = self.amount and (self.amount[lvl + 1] or self.amount[#self.amount]) or 0
	if amount <= 0 then return end
	local key = mechanics:getSpell():getJsonKey()
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			if unit:getTotalHealth() > unit:getAvailableHealth() then
				local amt, level = C.reviveHeal(unit, amount)
				if amt > 0 then server:healUnit(battle, unit, amt, level, ENUM.HealPower.permanent) end
			end
			local d = {
				type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h7:h7ElrathTouch", val = amount,
				duration = ENUM.BonusDuration.nTurns, turns = self.turns or 3,
				sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key, stacking = key .. "Touch"
			}
			if self.icon then d.icon = self.icon end
			server:addUnitBonus(battle, unit, d, false)
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- Hover estimate: same formula as apply, only the cast itself. Allies adjacent to the main target each heal amount[mastery] (with the Ring of Oblivion on the field only the top creature is healed),
--- healing is summed (the main target's resurrection is reported by the main effect of the same spell). The heals in the next two rounds are not counted
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local lvl = Lib.level(mechanics)
		local amount = self.amount and (self.amount[lvl + 1] or self.amount[#self.amount]) or 0
		if amount <= 0 then return zero end
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget or {})) do
			local unit = dest.unit
			if unit and unit:isAlive() and unit:getTotalHealth() > unit:getAvailableHealth() then
				local amt, level = C.reviveHeal(unit, amount)
				amt = math.floor(amt)
				if amt > 0 then
					local healed = unit:copy():heal(amt, level, ENUM.HealPower.permanent)
					out.hpDelta = out.hpDelta + (healed or 0)
				end
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
