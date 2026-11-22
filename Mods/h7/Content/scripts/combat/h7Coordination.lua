local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7AttackLib")
local M = require("heroes-memorial.h7:combat/h7SanctumLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Memorial Sanctum, Coordination (Dungeon ultimate Coordination; a permanent bonus on the hero, passed to the whole army).
--- Original: if a stack's first melee attack each round is not counterattacked, it immediately attacks the same target again for free (once per round).
---
--- How it works: the second hit is a real engine attack (damage formula, Luck, animation and all attack events as usual), using FEROCITY:
--- within an attack sequence the engine first strikes (the after-attack event runs here) -> checks FEROCITY -> then decides the counterattack.
--- So in the first hit's onAfterAttack, the counterattack is predicted with the engine's own conditions (still alive, ableToRetaliate,
--- no "no retaliation" on our side, not invincible); if there will be none, this attack gets FEROCITY (+1 attack, addInfo 0 = no kill required),
--- and the engine strikes the same target again at once. A first-strike counterattack (FIRST_STRIKE) already received also counts as "counterattacked".
--- "First melee attack each round": the first own melee attack this round (counterattacks and shots do not count); once used (triggered or not), not checked again this round.

local USED  = 3     -- Mark id: the first melee attack this round has happened
local RETAL = 4     -- Mark id: this stack was counterattacked during this action
local CAND  = 5     -- Mark id: this hit is a candidate
local STACK = "h7Coordination"

local function clear(server, battle, unit)
	L.removeByStacking(server, battle, unit, "FEROCITY", STACK)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if payload.isCounter then M.set(server, battle, unit, RETAL, 1, 1) end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.isCounter or payload.ranged or (payload.attackIndex or 0) ~= 0 then return end
	if M.get(unit, USED) ~= nil then return end
	M.set(server, battle, unit, USED, 1, 1)
	M.set(server, battle, unit, CAND, 1, 1)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or payload.ranged or (payload.attackIndex or 0) ~= 0 then return end
	if M.get(unit, CAND) == nil then return end
	M.clear(server, battle, unit, CAND)
	if not unit:isAlive() or other == nil or not other:isAlive() then return end
	if M.get(unit, RETAL) ~= nil then return end
	local willRetaliate = other:ableToRetaliate() and not unit:hasBonuses({ type = "BLOCKS_RETALIATION" })
		and not unit:isInvincible()
	if willRetaliate then return end
	server:addUnitBonus(battle, unit, {
		type = "FEROCITY", val = 1, addInfo = 0,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = STACK, hidden = true
	}, true)
	server:appendLog(battle, {
		append = { "core.bonus.H7_SANCTUM_H7C.description.3" },
		replaceStrings = { L.name(unit) },
		replaceNumbers = {}
	})
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	clear(server, battle, unit)
	M.clear(server, battle, unit, RETAL)
	M.clear(server, battle, unit, CAND)
end

return Script
