local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Spirit Form (H6 Lightweaver, Radiant Glory)
---
--- Added at battle start (after tactics deployment): attack and spell damage taken -val% each, shown as "Spirit Form" (H6_SPIRIT_FORM_H6C).
--- Removed after the stack's first real action (move, own attack, cast); defending and waiting do not count, nor do counterattacks.
--- Written like sanctSpiritForm of the Sanctum of the Abyss. Stacks summoned mid-battle do not get the battle start event and have no Spirit Form.
---
--- Parameter: val  damage reduction percentage, standard 50

local TAG = "h6SpiritForm"

local function remove(server, battle, unit)
	if not unit:hasBonuses({ type = "H6_SPIRIT_FORM_H6C" }) then return end
	L.removeByStacking(server, battle, unit, "H6_SPIRIT_FORM_H6C", TAG)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_REDUCTION", TAG)
	L.removeByStacking(server, battle, unit, "SPELL_DAMAGE_REDUCTION", TAG)
end

function Script:onBattleStart(server, battle, unit)
	if not unit:isAlive() or unit:hasBonuses({ type = "H6_SPIRIT_FORM_H6C" }) then return end
	local v = self.val or 50
	L.addBonus(server, battle, unit, { type = "H6_SPIRIT_FORM_H6C", val = v, stacking = TAG }, false)
	L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = v, stacking = TAG, hidden = true }, false)
	L.addBonus(server, battle, unit, { type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = v, stacking = TAG, hidden = true }, false)
end

function Script:onAfterMove(server, battle, unit)
	remove(server, battle, unit)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter then return end
	remove(server, battle, unit)
end

function Script:onUnitSpellcast(server, battle, unit)
	remove(server, battle, unit)
end

return Script
