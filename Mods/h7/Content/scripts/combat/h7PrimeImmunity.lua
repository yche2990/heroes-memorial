local Base = require("combat/combatScript")
local Imm = require("heroes-memorial.h7:combat/h7ImmuneLib")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Prime Immunity (Djinn, Djinn Vizier)
--- This pack has no Prime school: the 8 former Prime spells went to the four schools (Air Time Control/Fortune, Water Teleport/Dispel, Earth Implosion/Time Stasis, Fire Summon Elemental/Soul Fire);
--- the list is in h7ImmuneLib.PRIME. Against these 8 spells:
---   negative status spells get SPELL_IMMUNITY (cannot be targeted);
---   halved damage: MORE_DAMAGE_FROM_SPELL -val% (counted both by engine spell damage and Spell:adjustDamage);
---   negative spells actively cast on it are also removed afterwards as a fallback.
--- The creature JSON also has the hidden mark H7_PRIME_IMMUNITY_H7C (value = reduction percentage) for spell scripts that compute their own damage without the engine's spell damage.
--- Parameter: val (reduction percentage, default 50)

local KEY = "h7Imm|prime"

local function ensure(self, server, battle, unit)
	if not unit:isAlive() or unit:isGhost() then return end
	local all = Imm.existing(Imm.PRIME, false)
	local debuffs, extra = {}, {}
	for _, s in ipairs(all) do
		if s:isNegative() and not s:isDamage() then table.insert(debuffs, s) end
		table.insert(extra, { type = "MORE_DAMAGE_FROM_SPELL", subtype = Imm.subtype(s), val = -(self.val or 50) })
	end
	Imm.ensure(server, battle, unit, KEY, debuffs, nil, extra)
end

function Script:onBattleStart(server, battle, unit) ensure(self, server, battle, unit) end
function Script:onRoundStart(server, battle, unit) ensure(self, server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other ~= nil and other:unitID() == unit:unitID() then ensure(self, server, battle, unit) end
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local spell = payload.spell
	if spell == nil or not unit:isAlive() then return end
	ensure(self, server, battle, unit)
	if not Imm.inNames(spell, Imm.PRIME) or not Imm.shouldStrip(spell, nil) then return end
	if Imm.stripSpell(server, battle, unit, spell) > 0 then
		server:refreshBattleUnits(battle)
		A.log(server, battle, 5, { A.name(unit) }, {})
	end
end

return Script
