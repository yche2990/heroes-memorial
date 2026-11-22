local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Dark Purge (H6 Faceless Puppet Master): while it carries H6_PURGE_H6C (put on itself by the active ability "Dark Purge"; gone within the round after one attack),
--- enemies hit by its own attacks lose all beneficial spell effects. Parameters: animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or not unit:isAlive() or not unit:hasBonuses({ type = "H6_PURGE_H6C" }) then return end
	for _, t in ipairs(payload.targets or {}) do
		local u = t.unit
		if u and u:isAlive() and battle:isHostile(unit, u) then
			local list = u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
				local sp = LIBRARY:getSpellByName(b:getSourceID())
				return sp ~= nil and sp:isPositive()
			end)
			if list:size() > 0 then
				server:removeUnitBonuses(battle, u, list)
				L.show(server, battle, { u }, self.animation, self.sound)
			end
		end
	end
end

return Script
