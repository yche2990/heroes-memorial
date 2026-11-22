local Base = require("combat/combatScript")
local L = require("combat/h7dLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Bone Dragon, Spectral Dragon: Soul Reaver
---
--- Original: when its attacks kill enemy creatures, it takes 1 mana per creature from the enemy hero for its own hero; at most the own hero's "Magic" at a time.
--- Lua in this pack cannot change hero mana during battle, so it is approximated as:
---   the Bone Dragon's own attacks (not counterattacks) count val points per enemy creature killed, at most the own hero's Spell Power per attack (0 and no effect without a hero).
---   * The enemy hero loses mana: through the engine's MANA_DRAIN (when the stack's turn comes the enemy hero loses val mana, never below zero).
---     MANA_DRAIN is added when the Bone Dragon's action ends (2 rounds = drained once when the Bone Dragon's turn comes next round, removed at the start of the round after).
---   * The own hero gains mana: as Mana Drain, it becomes CHANGES_SPELL_COST_FOR_ALLY at the start of the next round (spells cost that much less this round).
---     The enemy hero's remaining mana cannot be read, so the own side gets the discount even when the enemy hero has too little mana (approximation).
--- Parameter: val (mana per creature, default 1)

local PENDING = "H7_MANA_PENDING_H7C"
local CREDIT = "H7_MANA_CREDIT_H7C"
local COST = "CHANGES_SPELL_COST_FOR_ALLY"
local TAG = "h7ManaCredit"
local DRAIN_PENDING = "h7SoulDrainPending"
local DRAIN = "h7SoulDrain"
local ANIM = "h7/fx/h7dManaDrain"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or payload.isCounter then return end
	local side = unit:getSide()
	local kills = 0
	for _, e in ipairs(payload.targets or {}) do
		local k = e.killed or 0
		if k > 0 and (e.unit == nil or e.unit:getSide() ~= side) then kills = kills + k end
	end
	if kills <= 0 then return end
	local cap = L.heroPower(unit)
	if cap <= 0 then return end
	local gain = math.min(kills * (self.val or 1), cap)
	L.setMark(server, battle, unit, PENDING, (L.markVal(unit, PENDING, TAG) or 0) + gain, nil, TAG, true)
	L.setMark(server, battle, unit, PENDING, (L.markVal(unit, PENDING, DRAIN_PENDING) or 0) + gain, nil, DRAIN_PENDING, true)
	server:showBattleAnimation(battle, { { unit = unit } }, ANIM, "", 1.0, true)
	server:refreshBattleUnits(battle)
	L.log(server, battle, 2, { L.name(unit) }, { gain, gain })
end

--- The Bone Dragon's own action ends: the stored "enemy hero loses mana" becomes MANA_DRAIN, drained by the engine when the Bone Dragon's turn comes next round
function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	if not unit:isAlive() then return end
	local n = L.markVal(unit, PENDING, DRAIN_PENDING) or 0
	if n <= 0 then return end
	L.clearMark(server, battle, unit, PENDING, DRAIN_PENDING)
	server:addUnitBonus(battle, unit, {
		type       = "MANA_DRAIN",
		val        = n,
		valueType  = ENUM.BonusValueType.additiveValue,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 2,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		hidden     = true
	}, true)
end

--- Round start: last round's savings become this round's "cost reduction" for the own hero
function Script:onRoundStart(server, battle, unit, other, payload)
	L.clearMark(server, battle, unit, COST, TAG)
	L.clearMark(server, battle, unit, CREDIT, TAG)
	if not unit:isAlive() then return end
	local have = L.markVal(unit, PENDING, TAG) or 0
	if have <= 0 then return end
	L.clearMark(server, battle, unit, PENDING, TAG)
	L.setMark(server, battle, unit, COST, have, 1, TAG, true)
	L.setMark(server, battle, unit, CREDIT, have, 1, TAG, false, { icon = "h7/abilities/h7SoulReaver" })
end

return Script
