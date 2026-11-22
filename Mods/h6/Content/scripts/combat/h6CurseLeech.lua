local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Spectral Dragon's curse, leech part (hidden battle-wide bonus, see spells/h6SpectralCurse): after a stack carrying H6_CURSED_H6C deals attack damage,
--- the Spectral Dragon that cursed it regains the same amount of health (can resurrect its creatures killed this battle). Parameters: none

function Script:onAfterAttack(server, battle, unit, other, payload)
	local list = unit:getBonuses({ type = "H6_CURSED_H6C" })
	if list:size() == 0 then return end
	local id = list:getBonus(1):getVal() - 1
	local total = 0
	for _, t in ipairs(payload.targets or {}) do total = total + (t.damage or 0) end
	if total <= 0 then return end
	local found = battle:getUnitsIf(function(u) return u:unitID() == id and u:isAlive() end)
	if found[1] then local amt, lvl = L.reviveHeal(found[1], total); server:healUnit(battle, found[1], amt, lvl, ENUM.HealPower.permanent) end   -- Ring of Oblivion
end

return Script
