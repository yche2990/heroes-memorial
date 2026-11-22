local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Implosion aftershock (H7 Expert Implosion = Prime Understanding III) (added by spells/h7Implosion, 2 rounds = triggers only once, at the start of the next round):
--- at the start of the next round it takes val% of its total health at that time as damage (counted at Expert level; the casting hero's bonuses and the target's resistance applied separately).
--- Parameters: side (casting side), spell

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() or unit:isInvincible() then return end
	local raw = unit:getAvailableHealth() * (self.val or 0) / 100 * (self.bonus or 100) / 100 -- H7 audit B1: multiplied by the hero's spell bonus at cast time
	local amount = E.spellDamage(battle, self.spell, self.side, unit, raw)
	if amount <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7eImplosionEcho", "h7/spell_implosion_impact.ogg", 1.0, true)
	local _, killed = server:damageUnit(battle, unit, amount)
	BattleLog.creaturesPerish(server, battle, unit, killed)
end

return Script
