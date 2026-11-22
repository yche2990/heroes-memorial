local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Martyrdom (H7): on the martyr (hidden, 3 rounds). When the martyr dies, the effects of this spell are removed from all stacks of the same side
--- (Morale +1 and the sharing script h7Martyr), unless another living martyr remains on that side. Death trigger, priority 100.

local MARK = "H7_MARTYR_H7C"
local KEY = "h7Martyr"

function Script:onDeath(server, battle, unit, other, payload)
	if unit:isAlive() then return end
	local side = unit:getSide()
	local myId = unit:unitID()
	local others = battle:getUnitsIf(function(u)
		return u:unitID() ~= myId and u:getSide() == side and u:isAlive() and u:hasBonuses({ type = MARK })
	end)
	if #others > 0 then return end
	local allies = battle:getUnitsIf(function(u)
		return u:getSide() == side and u:isAlive()
	end)
	for _, u in ipairs(allies) do
		local list = u:getBonuses({}):filter(function(b)
			return b:getSource() == ENUM.BonusSource.spellEffect and string.find(tostring(b:getSourceID() or ""), KEY, 1, true) ~= nil
		end)
		if list:size() > 0 then server:removeUnitBonuses(battle, u, list) end
	end
end

return Script
