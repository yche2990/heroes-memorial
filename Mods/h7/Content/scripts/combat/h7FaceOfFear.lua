local Base = require("heroes-memorial.h7:combat/h47Shove")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Face of Fear (H7): put on an ally by the spell h7FaceOfFear (heroes-memorial:h5Attach) for 3 rounds.
--- When this ally attacks an enemy on its own (not counterattacks):
---   1. Frighten away: after melee the target is pushed range hexes away from the attacker (inherits the knockback script h47Shove, copied unchanged into this mod;
---      pushed only after the whole action; cannot be pushed with a stack, obstacle or wall behind it or at the edge of the battlefield; war machines, arrow towers and charge-immune stacks are not affected).
---      In H7 shooting frightens too; here, as with the knockback, only melee pushes.
---   2. Fear: the enemy hit gets Morale -val (at least 1) for 3 rounds; repeated hits only refresh the rounds; mind-immune stacks and stacks unaffected by Morale are not affected.
---   3. noRetaliation = true (Expert, with Dark Understanding II): before the attack, the target cannot counterattack this round (NO_RETALIATION, 1 round).
--- Targets with "Indomitable" (H7_INDOMITABLE_H7C, the mark of this mod's batch A) are not affected by 1 and 2.
---
--- Parameters:
---   val            Morale reduction (computed from Spell Power at cast time)
---   mode, range, mark   as in h47Shove (mode = "push")
---   noRetaliation  Expert: the target cannot counterattack this round

local FEAR = "h7Fear"
local INDOMITABLE = "H7_INDOMITABLE_H7C"
local ANIM = "h7/fx/slFear"
local SOUND = "h7/spell_face_of_fear_tick.ogg"

local function victim(unit, other, payload)
	local t = other
	if t == nil and payload.targets and payload.targets[1] then t = payload.targets[1].unit end
	if t == nil or t:unitID() == unit:unitID() then return nil end
	return t
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if not self.noRetaliation or payload.isCounter then return end
	if not unit:isAlive() then return end
	local t = victim(unit, other, payload)
	if t == nil or not t:isAlive() or not L.hostile(battle, unit, t) then return end
	server:addUnitBonus(battle, t, {
		type = "NO_RETALIATION", val = 0,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = "h7FearNoRetal", hidden = true
	}, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	-- Frighten away: h47Shove uses val as the trigger chance, while val here is the Morale reduction, so it is temporarily set to 100% when borrowed
	-- Indomitable targets (H7_INDOMITABLE_H7C of batch A) are neither frightened away nor afraid
	local morale = math.max(1, self.val or 1)
	local t0 = victim(unit, other, payload)
	if t0 == nil or not L.has(t0, INDOMITABLE) then
		self.val = 100
		Base.onAfterAttack(self, server, battle, unit, other, payload)
		self.val = morale
	end

	if payload.isCounter then return end
	if (payload.attackIndex or 0) > 0 then return end
	local list = {}
	for _, e in ipairs(payload.targets or {}) do
		local t = e.unit
		if t and t:isAlive() and not t:isGhost() and t:unitID() ~= unit:unitID() and L.hostile(battle, unit, t)
			and not L.has(t, "MIND_IMMUNITY") and not L.has(t, "NO_MORALE") and not L.has(t, INDOMITABLE) then
			list[#list + 1] = t
		end
	end
	if #list == 0 then return end
	L.anim(server, battle, list, ANIM, SOUND, 0.85)
	for _, t in ipairs(list) do
		server:addUnitBonus(battle, t, {
			type = "MORALE", val = -morale,
			duration = ENUM.BonusDuration.nTurns, turns = 3,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
			stacking = FEAR
		}, false)
		server:addUnitBonus(battle, t, {
			type = "H7_FEAR_H7C", val = morale,
			duration = ENUM.BonusDuration.nTurns, turns = 3,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
			stacking = FEAR
		}, false)
	end
	server:refreshBattleUnits(battle)
end

return Script
