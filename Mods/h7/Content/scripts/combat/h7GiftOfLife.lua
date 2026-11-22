local Base = require("combat/combatScript")
local T = require("heroes-memorial.h7:combat/h7TreantSynergy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Gift of Life (Oak Dryad)
--- Design list: the Dryad's healing also works on healing war machines (Mother Tree = First Aid Tent).
--- When the Oak Dryad's own action ends, adjacent friendly healing machines (war machines with HEALER) also regain val x number of Dryads health.

local function isHealerMachine(u)
	return u:hasBonuses({ type = "HEALER" }) and u:hasBonuses({ type = "SIEGE_WEAPON" })
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() or not unit:isAlive() then return end
	T.healAdjacent(server, battle, unit, (self.val or 1) * unit:getCount(), isHealerMachine)
end

return Script
