--- Time Control (H7): the casting side's stacks Speed +X, enemy stacks Speed -X, for turns rounds (H7 Initiative +-5/7/10/15 converted by
--- this mod's ratio, median Speed 7 / median H7 Initiative 22, into +-2/2/3/5).
--- When the Expert area is larger, friends and foes in the area are hasted or slowed by their own side.
--- Slowing is a negative effect: enemies with NEGATIVE_EFFECTS_IMMUNITY or the Prime immunity mark H7_PRIME_IMMUNITY_H7C are unaffected.
--- Parameters:
---   values        4 numbers, by none/basic/advanced/expert
---   turns         rounds
---   animFast, animSlow, soundFast, soundSlow
local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Air = require("heroes-memorial.h7:spells/h7AirLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local PRIME_IMMUNE = "H7_PRIME_IMMUNITY_H7C"  -- Hidden mark of the batch A Djinn (the old name H7_PRIMEIMMUNE_H7C is also recognized)

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if Air.sideNum(unit:getSide()) ~= Air.sideNum(mechanics:getCasterSide()) then
		if Air.has(unit, PRIME_IMMUNE) or Air.has(unit, "H7_PRIMEIMMUNE_H7C") or Air.has(unit, "NEGATIVE_EFFECTS_IMMUNITY") then return false end
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local spellKey = mechanics:getSpell():getJsonKey()
	local lvl = Lib.level(mechanics)
	local x = self.values and (self.values[lvl + 1] or self.values[#self.values]) or 1
	local side = Air.sideNum(mechanics:getCasterSide())
	local describe = server:describeChanges()
	local any = false

	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() and self:isValidTarget(mechanics, unit) then
			local friendly = Air.sideNum(unit:getSide()) == side
			if describe then
				server:showBattleAnimation(battle, { { unit = unit } },
					friendly and self.animFast or self.animSlow,
					(friendly and self.soundFast or self.soundSlow) or "", 1.0, true)
			end
			server:addUnitBonus(battle, unit, {
				type       = "STACKS_SPEED",
				val        = friendly and x or -x,
				duration   = "N_TURNS",
				turns      = self.turns or 3,
				sourceType = "SPELL_EFFECT", sourceSecondaryID = mechanics:getEffectLevel(),
				sourceID   = spellKey,
				stacking   = spellKey
			}, false)
			any = true
		end
	end
	if any then server:refreshBattleUnits(battle) end
end

function Script:describeTargetStep()
	return nil
end

return Script
