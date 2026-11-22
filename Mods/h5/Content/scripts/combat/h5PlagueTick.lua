local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Plague (put on by the spells h5Plague / h5AbPlague): the stack takes val Earth damage at the end of each of its own actions.
--- val is already computed from SP at cast time (32 + 8 x SP). Invincible stacks are skipped.

function Script:onActionFinished(server, battle, unit, other, payload)
	if not other or other:unitID() ~= unit:unitID() then return end
	if not unit:isAlive() or unit:isInvincible() then return end
	local dmg = self.val or 0
	if dmg <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h5/fx/Spells_Plague", "", 0.8, true)
	server:damageUnit(battle, unit, dmg)
end

return Script
