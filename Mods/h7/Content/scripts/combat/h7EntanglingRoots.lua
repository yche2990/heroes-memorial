local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Entangling Roots (Ancient Treant)
---
--- Enemies hit by its attacks (ranged, melee, counterattacks) cannot move (BIND_EFFECT without the caster, so the engine does not release it when they are not adjacent),
--- until this Ancient Treant moves or dies. Stacks immune to Earth (or negative Earth spells) are not affected.
--- Stacking h7Entangle:<Treant id>; when the Treant moves or dies, this group is removed from the whole battlefield.

local function key(unit) return "h7Entangle:" .. tostring(unit:unitID()) end

function Script:release(server, battle, unit)
	local k = key(unit)
	local bound = battle:getUnitsIf(function(u) return u:isAlive() and u:hasBonuses({ type = "BIND_EFFECT" }) end)
	for _, u in ipairs(bound) do L.removeByStacking(server, battle, u, "BIND_EFFECT", k) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local hit = false
	for _, entry in ipairs(payload.targets or {}) do
		local t = entry.unit
		if (entry.damage or 0) > 0 and L.canHit(battle, unit, t) and not L.schoolImmune(t, "earth") then
			L.removeByStacking(server, battle, t, "BIND_EFFECT", key(unit))
			server:addUnitBonus(battle, t, {
				type = "BIND_EFFECT", val = 0,
				duration = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
				stacking = key(unit),
				icon = "h7/abilities/h7EntanglingRoots",
				description = "@core.bonus.H7_STATE_H7C.description.21"
			}, false)
			server:showBattleAnimation(battle, { { unit = t } }, "h7/fx/h7Entangle", "BIND", 1.0, true)
			L.log(server, battle, 9, { L.name(t) }, {})
			hit = true
		end
	end
	if hit then server:refreshBattleUnits(battle) end
end

function Script:onAfterMove(server, battle, unit, other, payload)
	self:release(server, battle, unit)
end

function Script:onDeath(server, battle, unit, other, payload)
	self:release(server, battle, unit)
end

return Script
