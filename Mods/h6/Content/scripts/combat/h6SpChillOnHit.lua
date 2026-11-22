--- Frost Armor (H6): after a stack with this effect is attacked in melee (counterattacks excluded), the attacker is Chilled (heroes-memorial:h6Chilled, original H6 status).
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or other == nil or not other:isAlive() then return end
	if not battle:isHostile(unit, other) or not server:describeChanges() then return end
	local sp = LIBRARY:getSpellByName("heroes-memorial:h6Chilled")
	if sp then server:castSpell(battle, unit:isAlive() and unit or other, sp, { other }, 0) end
end

return Script
