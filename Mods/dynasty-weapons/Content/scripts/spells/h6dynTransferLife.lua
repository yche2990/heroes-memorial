--- H6 Dynasty Weapon, Sandro's Staff level 5 "Transfer Life" (H6 Transfer Life, Ability 173550028):
---   once per battle; the target is a living own stack. For the rest of this battle, damage the hero's spells deal to living enemy stacks
---   restores percent% of it as health to this stack (healing only, no resurrection). The actual healing is done by the combat event script h6dynTransferLifeHit;
---   here the target only gets the hidden mark H6DYN_LIFELINK (val = percent) and a description for display.
--- Parameters: percent, onceIndex, bonusText (description shown on the stack, registered as translatable text)
local Base = require("spells/unitEffect")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:applicableGeneral(mechanics, problem)
	if Lib.used(mechanics, self.onceIndex or 2) then
		problem:addGeneric(mechanics)
		return false
	end
	return Base.applicableGeneral(self, mechanics, problem)
end

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) then return false end
	if unit:getBonusesValue({ type = "H6DYN_LIFELINK" }) > 0 then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

function Script:apply(mechanics, server, target)
	if not server:describeChanges() or #target == 0 then return end
	local battle = mechanics:getBattle()
	Lib.markUsed(mechanics, server, self.onceIndex or 2)
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			server:addUnitBonus(battle, unit, {
				type        = "H6DYN_LIFELINK",
				val         = self.percent or 50,
				duration    = ENUM.BonusDuration.oneBattle,
				sourceType  = ENUM.BonusSource.other,
				sourceID    = mechanics:getSpell():getJsonKey(),
				stacking    = "h6dynLifelink",
				hidden      = false,
				description = self.bonusText and ("@" .. self.bonusText) or nil,
				icon        = "h6dyn/spells/h6dynTransferLife/Effect"
			}, false)
		end
	end
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
