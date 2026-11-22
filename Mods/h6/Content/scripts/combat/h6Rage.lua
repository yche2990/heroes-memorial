local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Hatred of the Living (H6 Ghoul): damage +val% when attacking (counterattacks included) living creatures.
--- Before attacking it checks whether the target is alive; if so a temporary damage bonus is added and removed after the attack. Parameter: val

local TAG = "h6Rage"

function Script:onBeforeAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	if other == nil or not unit:isAlive() or not L.isLiving(other) then return end
	L.addBonus(server, battle, unit, {
		type = "GENERAL_DAMAGE_PREMY", val = self.val or 30,
		duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG, hidden = true
	}, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
end

return Script
