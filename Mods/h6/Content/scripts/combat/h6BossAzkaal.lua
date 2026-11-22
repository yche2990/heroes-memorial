local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Passives of Azkaal (H6 boss):
---   Luck Drain: each attack drains luck points of Luck from the target to itself (once per target, until the battle ends, cannot be dispelled);
---   Flames of Vengeance: enemies that attacked it this battle are remembered; when it counterattacks, the other remembered enemies also take one normal attack's damage each (scaled by Fire reduction).
--- Parameters: luck, animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local src = unit:getCreature():getJsonKey()
	for _, t in ipairs(payload.targets or {}) do
		local u = t.unit
		if u and u:isAlive() and battle:isHostile(unit, u) and not L.markValue(u, "h6LuckDrain" .. unit:unitID()) then
			L.setMark(server, battle, u, "h6LuckDrain" .. unit:unitID(), 1)
			server:addUnitBonus(battle, u, { type = "LUCK", val = -(self.luck or 1), duration = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other, sourceID = src }, true)
			server:addUnitBonus(battle, unit, { type = "LUCK", val = self.luck or 1, duration = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other, sourceID = src }, true)
			break
		end
	end
	if payload.isCounter and (payload.attackIndex or 0) == 0 then
		local main = payload.targets and payload.targets[1] and payload.targets[1].unit
		local key = "h6Venge" .. unit:unitID()
		local list = battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(unit, u) and L.markValue(u, key)
			and (main == nil or u:unitID() ~= main:unitID()) end)
		local total = 0
		for _, u in ipairs(list) do
			local a = math.floor(L.attackDamage(server, unit, u, 100, false) * (100 - L.schoolReduction(u, "fire")) / 100)
			total = total + (L.hit(server, battle, u, a, self.animation, self.sound) or 0)
		end
		if #list > 0 then L.log(server, battle, "H6_AREA_H6C", 7, { L.name(unit) }, { #list, total }) end
	end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if other == nil or payload.isCounter or not battle:isHostile(unit, other) then return end
	L.setMark(server, battle, other, "h6Venge" .. unit:unitID(), 1)
end

return Script
