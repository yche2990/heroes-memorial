local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shadow Form (H6 Dark Elemental): when its own attack hits an enemy, one random beneficial spell on it is dispelled (one spell = all effects of the same spell).
--- Parameters: animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or not unit:isAlive() or (payload.attackIndex or 0) > 0 then return end
	for _, t in ipairs(payload.targets or {}) do
		local u = t.unit
		if u and u:isAlive() and battle:isHostile(unit, u) then
			local bySpell, keys = {}, {}
			local all = u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect })
			for i = 1, all:size() do
				local b = all:getBonus(i); local id = b:getSourceID()
				local sp = LIBRARY:getSpellByName(id)
				if sp ~= nil and sp:isPositive() then
					if not bySpell[id] then bySpell[id] = {}; keys[#keys + 1] = id end
				end
			end
			if #keys > 0 then
				local pick = keys[server:rngInt(1, #keys)]
				local list = all:filter(function(b) return b:getSourceID() == pick end)
				server:removeUnitBonuses(battle, u, list)
				L.show(server, battle, { u }, self.animation, self.sound)
			end
			break
		end
	end
end

return Script
