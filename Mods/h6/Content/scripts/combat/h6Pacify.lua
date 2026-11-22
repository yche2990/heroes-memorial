local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Pacify (H6 Priestess, Sister)
---
--- After its own attack (not counterattacks) hits an enemy stack, applies the "Pacified" status to it (spell, level 3, 1 round):
--- cannot act or counterattack this round; being attacked ends it. Stacks immune to mind spells or to this spell are not affected.
---
--- Parameter: spell  full name of the Pacified status spell

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or payload.isCounter then return end
	if (payload.attackIndex or 0) > 0 then return end
	local entry = nil
	for _, t in ipairs(payload.targets or {}) do
		if t.unit then entry = t; break end
	end
	if entry == nil then return end
	local target = entry.unit
	if not L.real(target) or not battle:isHostile(unit, target) or target:isInvincible() then return end
	if target:hasBonuses({ type = "MIND_IMMUNITY" }) then return end
	local spell = L.spell(self.spell or "heroes-memorial.h6:h6Pacified")
	if spell == nil then return end
	server:applySpellEffects(battle, unit, spell, { target }, 3, 1, false)
	L.log(server, battle, "H6_PACIFY_H6C", 1, { L.name(unit), L.name(target) }, {})
end

return Script
