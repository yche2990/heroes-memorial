--- H6 Dynasty Weapon, Sword of the Wolf level 5 "Soul of the Wolf": in H6 the hero's Might +1 each round (stacks without limit).
--- Approximation: from round 2, own stacks get Attack +val every every rounds (cumulative within this battle). The counter is the hidden bonus H6DYN_ROUNDS on the stack.
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() or unit:isTurret() then return end
	local n = unit:getBonusesValue({ type = "H6DYN_ROUNDS" }) + 1
	Lib.setCounter(server, battle, unit, "H6DYN_ROUNDS", n)
	local every = self.every or 1
	if n % every ~= 0 then return end
	-- Only one per stacking group counts: read the old value, remove it, add back the total (Lib.addTotal)
	Lib.addTotal(server, battle, unit, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = self.val or 1,
		duration = "ONE_BATTLE", sourceType = "OTHER",
		description = self.text and ("@" .. self.text) or nil, icon = self.icon
	}, "h6dynRoundGrowth")
end

return Script
