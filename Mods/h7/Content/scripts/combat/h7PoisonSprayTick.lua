local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Poison Spray (H7) (added by the spell h7PoisonSpray through spells/h7EarthAttach): takes val Earth damage at the start of each round.
--- val is already adjusted by the spell damage flow at cast time (school reduction, magic reduction, vulnerability, hero spell bonus).
--- 4 rounds at none to Advanced (= the next 3 rounds), the whole battle at Expert. Invincible stacks are skipped.
--- In H7 the damage comes "when the stack's turn comes"; VCMI has no turn-start event for a single stack, so it is settled at the start of each round.

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() or unit:isInvincible() then return end
	local amount = self.val or 0
	if amount <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7ePoisonSprayTick", "h7/spell_poison_spray_impact.ogg", 1.0, true)
	local _, killed = server:damageUnit(battle, unit, amount)
	BattleLog.creaturesPerish(server, battle, unit, killed)
end

return Script
