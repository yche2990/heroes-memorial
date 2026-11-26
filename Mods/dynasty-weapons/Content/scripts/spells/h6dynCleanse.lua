--- H6 Dynasty Weapons: dispel by target side.
---   mode "side" (Staff of Purification "Purify"): own targets lose all negative spell effects, enemy targets all positive spell effects
---   mode "one"  (Nameless Staff "Nameless Curse", with stack attacks): removes one random positive spell effect from the enemy target
---   animAlly / animEnemy: hit effects
--- Like the core dispel, only bonuses with spell source (SPELL_EFFECT) count; adventure spells, persistent spells and this spell's own effects do not.
local Base = require("spells/dispel")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function own(mechanics, unit)
	return unit:getSide() == mechanics:getCasterSide()
end

function Script:getDispelableBonuses(mechanics, unit)
	local p, n, u = self.dispelPositive, self.dispelNegative, self.dispelNeutral
	local mine = own(mechanics, unit)
	self.dispelPositive = not mine
	self.dispelNegative = mine and self.mode ~= "one"
	self.dispelNeutral = false
	local list = Base.getDispelableBonuses(self, mechanics, unit)
	self.dispelPositive, self.dispelNegative, self.dispelNeutral = p, n, u
	return list
end

function Script:isValidTarget(mechanics, unit)
	if self.mode == "one" and own(mechanics, unit) then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local animated = false
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit then
			local bonuses = self:getDispelableBonuses(mechanics, unit)
			if bonuses:size() > 0 then
				if self.mode == "one" then
					local pick = bonuses:getBonus(server:rngInt(1, bonuses:size())):getSourceID()
					bonuses = bonuses:filter(function(b) return b:getSourceID() == pick end)
				end
				local anim = own(mechanics, unit) and self.animAlly or self.animEnemy
				animated = (server:describeChanges() and Lib.anim(server, battle, unit, anim)) or animated
				server:removeUnitBonuses(battle, unit, bonuses)
			end
		end
	end
	if animated then server:refreshBattleUnits(battle) end
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
