local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Hex of Disruption (Lich Master)
---
--- After shooting (counterattacks excluded), the main target and all enemies adjacent to it get Defense -val until each has acted turns more times (default 2).
--- Stacks immune to Dark (or negative Dark spells) are not affected. Repeated hits only refresh, no stacking.
--- Parameters: val (Defense reduction, already scaled by level), turns

function Script:onBattleStart(server, battle, unit, other, payload)
	L.ensureTracker(server, battle, unit)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter or not unit:isAlive() or other == nil then return end
	-- Even if the main target is killed, the enemies around it are still affected
	local victims = {}
	if L.canHit(battle, unit, other) and not L.schoolImmune(other, "dark") then table.insert(victims, other) end
	for _, o in ipairs(L.adjacentUnits(battle, other, function(u)
		return L.canHit(battle, unit, u) and not L.schoolImmune(u, "dark")
	end)) do
		table.insert(victims, o)
	end
	if #victims == 0 then return end
	local v = self.val or 10
	local src = unit:getCreature():getJsonKey()
	for _, t in ipairs(victims) do
		local turns = L.turnsFor(t, self.turns or 2, false)
		L.removeByStacking(server, battle, t, "PRIMARY_SKILL", "h7HexOfDisruption")
		server:addUnitBonus(battle, t, {
			type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = -v, hidden = true,
			duration = ENUM.BonusDuration.nTurns, turns = turns,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h7HexOfDisruption"
		}, false)
		L.setShow(server, battle, t, "H7_DISRUPT_H7C", v, turns, "h7HexOfDisruption", src)
		server:showBattleAnimation(battle, { { unit = t } }, "h7/fx/h7Disruption", "", 1.0, true)
	end
	server:refreshBattleUnits(battle)
end

return Script
