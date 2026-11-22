--- H6 Dynasty Weapons: records the damage a stack has dealt since battle start (hidden bonus H6DYN_DEALT, cumulative), for "Thorn of Regret".
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onAfterAttack(server, battle, unit, other, payload)
	local total = 0
	for _, t in ipairs(payload.targets or {}) do total = total + (t.damage or 0) end
	if total <= 0 or not unit:isAlive() then return end
	-- Only one per stacking group counts: read the old value, remove it, add back the total (Lib.addTotal), added up on every attack
	Lib.addTotal(server, battle, unit, {
		type = "H6DYN_DEALT", val = total, duration = "ONE_BATTLE", sourceType = "OTHER", hidden = true
	}, "h6dynDealt")
end

return Script
