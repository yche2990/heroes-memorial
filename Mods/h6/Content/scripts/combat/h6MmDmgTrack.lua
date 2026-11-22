--- Divine Judgment (H6 Memorial Sanctum, Haven) bookkeeping: battle-wide hidden script the hero carries after learning it (BATTLE_WIDE, stacking h6MmDmgTrack, counted once).
--- After each attack (counterattacks and second strikes included), the damage dealt is added to the attacker's hidden mark h6MmDealt (whole battle).
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onAfterAttack(server, battle, unit, other, payload)
	local total = 0
	for _, t in ipairs(payload.targets or {}) do total = total + (t.damage or 0) end
	if total <= 0 or unit:isTurret() then return end
	L.setMark(server, battle, unit, "h6MmDealt", (L.markValue(unit, "h6MmDealt") or 0) + total)
end

return Script
