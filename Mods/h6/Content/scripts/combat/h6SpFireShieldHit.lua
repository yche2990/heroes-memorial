--- Fire Shield (H6): after a stack with this effect is attacked in melee (counterattacks excluded), the attacker takes perCreature Fire damage per creature (Fire reduction and immunity as the Fire Shield spell).
--- Parameters: perCreature, spell (full name of the Fire Shield spell)
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or other == nil or not other:isAlive() or not battle:isHostile(unit, other) then return end
	if not battle:isMeleeAttackPossible(other, unit) then return end
	local sp = LIBRARY:getSpellByName(self.spell or "")
	local raw = other:getCount() * (self.perCreature or 1)
	local dmg = raw
	if sp then
		local ok, v = pcall(function() return sp:adjustDamage(battle, unit, other, raw) end)
		if ok and v then dmg = v end
	end
	if dmg <= 0 then return end
	if server:describeChanges() then server:showBattleAnimation(battle, { { unit = other } }, "C05SPF0", "FIRESHIE", 1.0, true) end
	server:damageUnit(battle, other, dmg)
end

return Script
