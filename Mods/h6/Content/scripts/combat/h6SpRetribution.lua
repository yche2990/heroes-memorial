--- Retribution Aura (H6): after being attacked in melee (counterattacks excluded), val% (at most 30%) of the damage taken is returned to the attacker as Light damage. Parameter: spell (full spell name)
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or other == nil or not other:isAlive() or not battle:isHostile(unit, other) then return end
	local entry = self:ownEntry(unit, payload)
	if entry == nil or (entry.damage or 0) <= 0 then return end
	local raw = math.floor(entry.damage * math.min(self.val or 0, 30) / 100)
	if raw <= 0 then return end
	local sp = LIBRARY:getSpellByName(self.spell or "")
	local dmg = raw
	if sp then
		local ok, v = pcall(function() return sp:adjustDamage(battle, unit, other, raw) end)
		if ok and v then dmg = v end
	end
	if dmg > 0 then server:damageUnit(battle, other, dmg) end
end

return Script
