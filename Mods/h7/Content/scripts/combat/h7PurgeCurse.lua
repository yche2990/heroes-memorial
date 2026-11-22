local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Purge (H7) Expert "curse": added by the spell h7Purge (heroes-memorial:h5Attach), lasting 3 rounds.
--- Meanwhile the stack cannot receive beneficial spells: when hit by an actively cast beneficial spell (hero or creature casts, onSpellHit), all effects that spell left are removed at once.
--- Spells cast with attacks or by scripts do not send onSpellHit and cannot be blocked (the engine has no immunity bonus that blocks only beneficial spells).

local ANIM = "h7/fx/slPurgeCurse"
local SOUND = "h7/spell_purge.ogg"

function Script:onSpellHit(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local spell = payload.spell
	if spell == nil or not spell:isPositive() then return end
	local key = spell:getJsonKey()
	local list = unit:getBonuses({}):filter(function(b)
		return b:getSource() == ENUM.BonusSource.spellEffect and b:getSourceID() == key
	end)
	if list:size() == 0 then return end
	L.anim(server, battle, { unit }, ANIM, SOUND, 0.85)
	server:removeUnitBonuses(battle, unit, list)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus.H7_SL_LOG_H7C.description.4" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()), spell:getNameTextID() }
	})
end

return Script
