local Base = require("combat/combatScript")
local L = require("combat/h7dLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Djinn, Djinn Vizier: Mana Drain
---
--- Original: for each enemy creature the Djinn kills, its hero regains 1 mana; at most the hero's "Magic" per attack.
--- Lua in this pack cannot change hero mana during battle, so it is approximated as a "mana discount":
---   the Djinn (counterattacks included) gains val points per enemy creature killed (at most the hero's Spell Power per attack), stored in the hidden mark H7_MANA_PENDING_H7C on the Djinn;
---   at the start of the next round it turns into CHANGES_SPELL_COST_FOR_ALLY (the friendly hero's spells cost that much less mana, this round only),
---   together with H7_MANA_CREDIT_H7C for display. Unused points are not kept. No effect without a hero (Spell Power 0).
---   For "cost reduction" from several friendly stacks the engine takes the maximum, not the sum.
--- Parameter: val (mana per creature, default 1)

local PENDING = "H7_MANA_PENDING_H7C"
local CREDIT = "H7_MANA_CREDIT_H7C"
local COST = "CHANGES_SPELL_COST_FOR_ALLY"
local TAG = "h7ManaCredit"
local ANIM = "h7/fx/h7dManaDrain"

local function killsOnEnemies(unit, payload)
	local side = unit:getSide()
	local n = 0
	for _, e in ipairs(payload.targets or {}) do
		local k = e.killed or 0
		if k > 0 and (e.unit == nil or e.unit:getSide() ~= side) then n = n + k end
	end
	return n
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local kills = killsOnEnemies(unit, payload)
	if kills <= 0 then return end
	local cap = L.heroPower(unit)
	if cap <= 0 then return end
	local gain = math.min(kills * (self.val or 1), cap)
	local have = L.markVal(unit, PENDING, TAG) or 0
	L.setMark(server, battle, unit, PENDING, have + gain, nil, TAG, true)
	server:showBattleAnimation(battle, { { unit = unit } }, ANIM, "", 1.0, true)
	server:refreshBattleUnits(battle)
	L.log(server, battle, 1, { L.name(unit) }, { gain })
end

--- Round start: last round's savings become this round's "cost reduction"
function Script:onRoundStart(server, battle, unit, other, payload)
	L.clearMark(server, battle, unit, COST, TAG)
	L.clearMark(server, battle, unit, CREDIT, TAG)
	if not unit:isAlive() then return end
	local have = L.markVal(unit, PENDING, TAG) or 0
	if have <= 0 then return end
	L.clearMark(server, battle, unit, PENDING, TAG)
	L.setMark(server, battle, unit, COST, have, 1, TAG, true)
	L.setMark(server, battle, unit, CREDIT, have, 1, TAG, false, { icon = "h7/abilities/h7ManaDrain" })
end

return Script
