local Base = require("combat/combatScript")
local L = require("combat/h7SfLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 "Burning" (added by Expert Firebolt, Fireball and Fire Wall; heroes-memorial:h5Attach computes val from Magic at cast time):
--- the stack takes val Fire damage when its first own action each round ends (in H7 when its turn comes; VCMI has no "turn comes" event,
--- so as H5's Curse of Decay it is placed at the end of its own action, counted once even when acting after waiting: this-round mark H7_BURN_TICKED_H7C).
--- Stacks with Fire immunity, negative Fire immunity, immunity to the spell that cast it, or invincibility take no damage; Fire damage reduction applies.
--- Parameter: spell (the spell that cast it, used to check SPELL_IMMUNITY)

local MARK = "H7_BURN_TICKED_H7C"

function Script:onActionFinished(server, battle, unit, other, payload)
	if not other or other:unitID() ~= unit:unitID() then return end
	if not unit:isAlive() or unit:isGhost() then return end
	if unit:hasBonuses({ type = MARK }) then return end
	local raw = self.val or 0
	if raw <= 0 then return end
	L.setMark(server, battle, unit, MARK, 1, 1)
	if L.fireImmune(unit, self.spell) then return end
	local dmg = L.fireDamage(unit, raw)
	if dmg <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/sfBurning", "h7/sf_burning_tick.ogg", 1.0, true)
	server:damageUnit(battle, unit, dmg)
end

return Script
