local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Rooting (Shantiri Titan)
---
--- Enemies hit by its attacks (ranged, melee, counterattacks) get Speed -speed until they have acted turns more times (default 2);
--- on a critical hit (lucky strike; chance see h7StatusLib.crit) enemies hit cannot move at all until the end of their next action (BIND_EFFECT).
--- Stacks immune to Earth (or negative Earth spells) are not affected. Repeated hits only refresh the rounds, no stacking.
--- Parameters: speed (default 3), turns (default 2)

function Script:onBattleStart(server, battle, unit, other, payload)
	L.ensureTracker(server, battle, unit)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local victims = {}
	for _, entry in ipairs(payload.targets or {}) do
		local t = entry.unit
		if (entry.damage or 0) > 0 and L.canHit(battle, unit, t) and not L.schoolImmune(t, "earth") then
			table.insert(victims, t)
		end
	end
	if #victims == 0 then return end
	L.ensureTracker(server, battle, unit)
	local crit = L.crit(server, battle, unit)
	local src = unit:getCreature():getJsonKey()
	local speed = self.speed or 3
	for _, t in ipairs(victims) do
		local turns = L.turnsFor(t, self.turns or 2, payload.isCounter)
		L.removeByStacking(server, battle, t, "STACKS_SPEED", "h7Rooting")
		server:addUnitBonus(battle, t, {
			type = "STACKS_SPEED", val = -speed, hidden = true,
			duration = ENUM.BonusDuration.nTurns, turns = turns,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h7Rooting"
		}, false)
		L.setShow(server, battle, t, "H7_ROOTED_H7C", speed, turns, "h7Rooting", src)
		if crit then
			local bt = L.turnsFor(t, 1, payload.isCounter)
			L.removeByStacking(server, battle, t, "BIND_EFFECT", "h7RootingBind")
			server:addUnitBonus(battle, t, {
				type = "BIND_EFFECT", val = 0,
				duration = ENUM.BonusDuration.nTurns, turns = bt,
				sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h7RootingBind",
				icon = "h7/abilities/h7Rooting",
				description = "@core.bonus.H7_STATE_H7C.description.20"
			}, false)
			L.log(server, battle, 8, { L.name(t) }, {})
		end
		server:showBattleAnimation(battle, { { unit = t } }, "h7/fx/h7Rooting", crit and "BIND" or "", 1.0, true)
	end
	server:refreshBattleUnits(battle)
end

return Script
