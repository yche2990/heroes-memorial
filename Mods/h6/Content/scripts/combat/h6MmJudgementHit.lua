--- Moment of Judgment (H6 Memorial Sanctum, Haven): damage +val% when attacking an enemy with Anathema (H6_MM_STATUS_H6C, stacking h6MmAnathema); the target's Anathema is removed after the attack.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local TAG = "h6MmJudgementDmg"

function Script:onBeforeAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	if other == nil or not unit:isAlive() or not battle:isHostile(unit, other) or not M.cursed(other) then return end
	L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = self.val or 0, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG, sourceType = ENUM.BonusSource.other }, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and battle:isHostile(unit, t.unit) and M.cursed(t.unit) then M.clearAnathema(server, battle, t.unit) end
	end
end

return Script
