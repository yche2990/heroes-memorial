--- H6 Dynasty Weapon, Crystal Rose Staff level 4 "Liandra's Resolve": when an own stack's count drops below pct% of the starting count, it gets "Ignore Pain":
--- damage taken this battle -val% (approximation). Once per stack.
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onActionFinished(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isTurret() then return end
	if unit:getBonusesValue({ type = "H6DYN_RESOLVE" }) > 0 then return end
	if unit:getCount() * 100 >= unit:getBaseAmount() * (self.pct or 20) then return end
	server:addUnitBonus(battle, unit, {
		type = "H6DYN_RESOLVE", val = 1, duration = "ONE_BATTLE", sourceType = "OTHER", hidden = true
	}, false)
	server:addUnitBonus(battle, unit, {
		type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = self.val or 30,
		duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h6dynResolve",
		description = self.text and ("@" .. self.text) or nil, icon = self.icon
	}, false)
end

return Script
