--- Lightning Burst (H7): puts the combat event h7AirBurst (hidden) on the target, which discharges at its next action.
--- Spell Power and mastery level are recorded at cast time: bonus value = 1000000 + level*100000 + SP (the effect value passed to server:castSpell,
--- from which h5SpellLib decodes the fixed SP and level); addInfo additionally records the casting side (Expert only hurts the casting side's enemies).
--- Parameters:
---   eventScript   combat event script name
---   hitSpell      damage spell cast on discharge
---   turns         how long it lasts (H7 says "until it discharges"; a long enough number of rounds is given here)
local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Air = require("heroes-memorial.h7:spells/h7AirLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local spellKey = mechanics:getSpell():getJsonKey()
	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local encoded = Lib.ENCODED + lvl * 100000 + math.max(0, math.min(99999, sp))
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			server:addUnitBonus(battle, unit, {
				type       = "COMBAT_EVENT_TRIGGER",
				subtype    = self.eventScript,
				val        = encoded,
				duration   = "N_TURNS",
				turns      = self.turns or 50,
				sourceType = "SPELL_EFFECT", sourceSecondaryID = mechanics:getEffectLevel(),
				sourceID   = spellKey,
				stacking   = spellKey,
				hidden     = true,
				addInfo    = { casterSide = Air.sideNum(mechanics:getCasterSide()), expert = lvl >= 3, hitSpell = self.hitSpell }
			}, false)
		end
	end
end

function Script:describeTargetStep()
	return nil
end

return Script
