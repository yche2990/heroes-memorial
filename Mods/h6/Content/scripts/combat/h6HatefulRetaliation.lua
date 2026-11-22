local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Hateful Retaliation (H6 Pit Fiend, Pit Lord)
---
--- Enemies that attacked it (counterattacks included) are remembered (whole battle). Each time it counterattacks, besides the counterattack's target, every other remembered enemy also takes
--- Fire damage equal to its normal attack on that stack (scaled by Fire and all-spell reduction). Parameters: animation, sound

local function key(unit) return "h6Hate" .. tostring(unit:unitID()) end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if other == nil or not other:isAlive() or not battle:isHostile(unit, other) then return end
	if L.markValue(other, key(unit)) == nil then L.setMark(server, battle, other, key(unit), 1) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.isCounter or not unit:isAlive() then return end
	local skip = {}
	for _, t in ipairs(payload.targets or {}) do if t.unit then skip[t.unit:unitID()] = true end end
	local k = key(unit)
	local list = battle:getUnitsIf(function(u)
		return L.real(u) and battle:isHostile(unit, u) and not skip[u:unitID()] and L.markValue(u, k) ~= nil
	end)
	local total, n = 0, 0
	for _, u in ipairs(list) do
		local amount = math.floor(L.attackDamage(server, unit, u, 100, false) * (100 - L.schoolReduction(u, "fire")) / 100)
		if amount > 0 then
			total = total + (L.hit(server, battle, u, amount, self.animation, self.sound) or 0); n = n + 1
		end
	end
	if n > 0 then L.log(server, battle, "H6_HATEFUL_H6C", 1, { L.name(unit) }, { n, total }) end
end

return Script
