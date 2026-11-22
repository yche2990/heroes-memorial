local Base = require("combat/combatScript")
local Imm = require("heroes-memorial.h7:combat/h7ImmuneLib")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 X Immunity (Fire, Water, Air, Earth, Light, Dark) and Magic Immunity (Gargoyle, Black Dragon)
--- Original: cannot be targeted by negative spells (statuses) of that school, and that school's damage is halved (halving is the SPELL_DAMAGE_REDUCTION in the creature JSON, not handled here).
--- How it works, see combat/h7ImmuneLib: at battle start a SPELL_IMMUNITY list (that school's negative status spells) is added, and statuses from actively cast spells landing on it are removed as a fallback.
--- Parameter: school (fire / water / earth / air / light / dark; omitted or "any" = any school, i.e. magic immunity)

local function school(self) return self.school or "any" end
local function key(self) return "h7Imm|" .. school(self) end

local function ensure(self, server, battle, unit)
	if not unit:isAlive() or unit:isGhost() then return end
	Imm.ensure(server, battle, unit, key(self), Imm.debuffs(school(self)))
end

function Script:onBattleStart(server, battle, unit) ensure(self, server, battle, unit) end
function Script:onRoundStart(server, battle, unit) ensure(self, server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other, payload)
	-- Stacks appearing mid-battle (summons, clones) get it after their first action
	if other ~= nil and other:unitID() == unit:unitID() then ensure(self, server, battle, unit) end
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local spell = payload.spell
	if spell == nil or not unit:isAlive() then return end
	ensure(self, server, battle, unit)
	if not Imm.shouldStrip(spell, school(self)) then return end
	if Imm.stripSpell(server, battle, unit, spell) > 0 then
		server:refreshBattleUnits(battle)
		A.log(server, battle, 5, { A.name(unit) }, {})
	end
end

return Script
