--- H6 Dynasty Weapon, Void Staff level 2 "Netherchannel" (H6 Netherchannel: steals 2 mana from the enemy hero each round, ManaTransfer to its own hero).
--- The engine settles MANA_DRAIN per stack: every stack carrying it drains once at the start of its own action (BattleFlowProcessor::stackTurnTrigger),
--- so giving MANA_DRAIN directly from the weapon would pass it to all stacks, making it 2 x stack count. Here it is settled per hero instead, draining val only once per round:
---   - at battle start and the start of each round, every own stack gets MANA_DRAIN val valid for this round (N_TURNS 1, removed and reattached at the start of next round);
---   - once any own stack has acted (after draining once), all other own stacks are marked "already drained this round" (drainedMana),
---     so the engine no longer lets them drain. The engine clears this mark at the start of a new round.
--- Limitation: Lua has no interface to change hero mana (only adventure map scripts can), so the drained mana cannot go to the own hero; the enemy hero just loses it.
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local TAG = "h6dynManaDrain"

function Script:arm(server, battle, unit)
	if not unit:isAlive() or unit:isTurret() then return end
	if Lib.byStacking(unit, { type = "MANA_DRAIN" }, TAG):size() > 0 then return end
	server:addUnitBonus(battle, unit, {
		type = "MANA_DRAIN", val = self.val or 2, duration = "N_TURNS", turns = 1, sourceType = "OTHER", stacking = TAG, hidden = true
	}, false)
end

function Script:onBattleStart(server, battle, unit)
	self:arm(server, battle, unit)
end

function Script:onRoundStart(server, battle, unit)
	self:arm(server, battle, unit)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	-- Review B12 (2026-11-08): the engine sends ACTION_FINISHED to every participant of this action (those hit and retaliating too),
	-- so only its own action is handled (other is the actor); otherwise an own stack hit by the enemy before acting would mark its companions as "already drained".
	-- A stack that died during its action is still handled (it drained when its action began); a living one without this MANA_DRAIN (summoned mid-round) did not drain and is not handled
	if other == nil or other:unitID() ~= unit:unitID() then return end
	if unit:isAlive() and Lib.byStacking(unit, { type = "MANA_DRAIN" }, TAG):size() == 0 then return end
	local side = unit:getSide()
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() and not x:isTurret() end)) do
		if u:unitID() ~= unit:unitID() and Lib.byStacking(u, { type = "MANA_DRAIN" }, TAG):size() > 0 then
			local s = u:copy()
			s:setDrainedMana(true)
			server:changeUnit(battle, s)
		end
	end
end

return Script
