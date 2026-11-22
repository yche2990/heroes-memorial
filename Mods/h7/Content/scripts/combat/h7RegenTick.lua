local Base = require("combat/combatScript")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Regeneration (H7) (added by the spell h7Regeneration through spells/h7EarthAttach for 4 rounds = the next 3 rounds):
--- regains val health at the start of each round and can resurrect the stack's dead creatures (permanent). With the Ring of Oblivion (HOTA_RING_OF_OBLIVION) only the top creature is healed, no resurrection.
--- In H7 healing comes "when the stack's turn comes"; VCMI has no turn-start event for a single stack, so it is settled at the start of each round.

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local amount = self.val or 0
	if amount <= 0 then return end
	if unit:getTotalHealth() <= unit:getAvailableHealth() then return end
	E.anim(server, battle, { unit }, "h7/fx/h7eRegenTick", "h7/spell_regeneration_tick.ogg", true)
	E.revive(server, battle, unit, amount)
	server:refreshBattleUnits(battle)
end

return Script
