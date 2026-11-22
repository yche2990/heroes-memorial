local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Attacks with a status (H6 Skeleton Spearman "Spear Web", Lich "Dark Embrace")
---
--- After its own attack (melee or ranged; counterattacks do not count; for double attacks only the first hit) hits an enemy stack, applies the status spell spell to it
--- (level 3, lasting turns rounds); if adjacent is true, the other enemies adjacent to it are affected too. Stacks immune to this spell are not affected.
---
--- Parameters: spell (full name of the status spell), turns, adjacent, animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or payload.isCounter then return end
	if (payload.attackIndex or 0) > 0 then return end
	local entry = nil
	for _, t in ipairs(payload.targets or {}) do
		if t.unit then entry = t; break end
	end
	if entry == nil then return end
	local target = entry.unit
	if not L.real(target) or not battle:isHostile(unit, target) then return end
	local spell = L.spell(self.spell)
	if spell == nil then return end
	local list = { target }
	if self.adjacent then
		for _, u in ipairs(L.around(battle, target, function(u) return battle:isHostile(unit, u) end)) do list[#list + 1] = u end
	end
	server:applySpellEffects(battle, unit, spell, list, 3, self.turns or 2, false)
	L.show(server, battle, list, self.animation, self.sound)
end

return Script
