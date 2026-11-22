local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Ab = require("spells/h7abLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 statuses, tracking and settlement (shared script of batch B)
---
--- Added to the battlefield by h7StatusLib.ensureTracker (hidden, carried by every stack, one copy per battle). Handles:
---   1. whether each stack has already acted this round (waiting does not count), for effects lasting "until the end of its next action";
---   2. which stack of which side hit each stack this round (for Backstab);
---   3. settling damage over time at the start of each round (Acid Breath, Withering Breath, Withering Venom, Poisoned Blades).
--- All these marks are 1-round hidden H7_STATE_H7C, removed automatically by the engine at the start of the next round.

function Script:onWait(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	L.setMark(server, battle, unit, "h7Waited", 1, 1)
end

--- Casts that do not use the turn (preparation / charge abilities, see spells/h7abLib.markNoSkip) count like waiting: not counted as having acted this round
function Script:onUnitSpellcast(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	if L.noSkipCast(unit) then L.setMark(server, battle, unit, "h7Waited", 1, 1) end
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() or not unit:isAlive() then return end
	L.clearNoSkipCast(server, battle, unit)
	if L.markValue(unit, "h7Waited") ~= nil then
		L.clearMark(server, battle, unit, "h7Waited")
		return
	end
	if not L.acted(unit) then L.setMark(server, battle, unit, "h7Acted", 1, 1) end
end

--- The creature active ability "prepare the next attack" (spells/h7AbArm, stacking h7AbArm) only applies to its own attacks:
--- if, after preparing (wait, defend), it is attacked by an enemy first, the mark is removed and counterattacks do not get the prepared effect (review R1). Not removed when being counterattacked (isCounter); second attacks still get it
local ARMED = { "H7_NOVA_ARMED_H7C", "H7_SCATTER_ARMED_H7C", "H7_HAMMER_ARMED_H7C", "H7_LEAF_ARMED_H7C",
	"H7_IMPLODE_ARMED_H7C", "H7_INK_ARMED_H7C", "H7_STING_ARMED_H7C" }
function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if payload == nil or payload.isCounter or not unit:isAlive() then return end
	local removed = false
	for _, typeName in ipairs(ARMED) do
		local ok, has = pcall(function() return unit:hasBonuses({ type = typeName }) end)
		if ok and has then L.removeByStacking(server, battle, unit, typeName, "h7AbArm"); removed = true end
	end
	-- H7 audit (Yu's decision 2a): if interrupted after preparing and before striking, the "once per battle" use is refunded
	if removed then Ab.armRefund(server, battle, unit, false) end
end

--- Its own attack (not a counterattack): this preparation is used up
function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload == nil or payload.isCounter then return end
	Ab.armConsumed(server, battle, unit)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if other == nil or not unit:isAlive() then return end
	local key = L.hitKey(other)
	local id = other:unitID() + 1
	local old = L.markValue(unit, key)
	if old == nil then
		L.setMark(server, battle, unit, key, id, 1)
	elseif old ~= id and old ~= -1 then
		L.setMark(server, battle, unit, key, -1, 1)
	end
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	Ab.armRefund(server, battle, unit, true) -- H7 audit 2a: a preparation not used last round and removed on expiry gets its use refunded
	L.tickDots(server, battle, unit)
end

return Script
