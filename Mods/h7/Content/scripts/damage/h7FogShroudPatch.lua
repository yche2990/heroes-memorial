local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Heroes VII creatures and spells (heroes-memorial.h7) damage patch: Mist Veil (H7)
---   H7_FOGSHROUD_H7C  the target is shrouded in mist; shots at it deal 0 damage (H7: cannot be targeted by ranged attacks)

local FOG = "H7_FOGSHROUD_H7C"

function Script:getDamageCap(info)
	local cap = Base.getDamageCap(self, info)
	if info.shooting and self:hasBonusOfType(info.defenderBonuses, FOG) then
		return 0
	end
	return cap
end

Script:declareBonus(FOG)

return Script
