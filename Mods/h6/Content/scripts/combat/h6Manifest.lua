local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Manifest (H6 Light Elemental): after each counterattack it gives off light: adjacent enemies take per x own stack size Light damage,
--- and adjacent allies regain the same amount of health (no resurrection). Parameters: per, animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.isCounter or not unit:isAlive() then return end
	local amount = (self.per or 3) * unit:getCount()
	for _, u in ipairs(L.around(battle, unit, function(u) return L.real(u) end)) do
		if battle:isHostile(unit, u) then
			local a = math.floor(amount * (100 - L.schoolReduction(u, "01lightSchool")) / 100)
			if a > 0 then L.hit(server, battle, u, a, self.animation, self.sound) end
		else
			server:healUnit(battle, u, amount, ENUM.HealLevel.heal, ENUM.HealPower.oneBattle)
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
