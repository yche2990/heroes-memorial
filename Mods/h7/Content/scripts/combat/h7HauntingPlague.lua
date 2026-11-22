local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Haunting Plague (H7): the spell h7HauntingPlague puts this hidden script on every (non-immune) enemy stack at cast time, for 4 rounds.
--- At the start of each later round, the first stack with this script to run settles for the whole battlefield (the others skip that round, via the hidden mark H7_HAUNT_ROUND_H7C):
---   1. Stacks possessed last round (visible mark H7_HAUNTED_H7C) take Dark damage "at round end": settled here at the start of the next round,
---      damage = the mark's value, adjusted by the target's Dark / all-school spell damage reduction; then the mark is removed.
---   2. At the start of the first two rounds after casting (this script has >= 2 rounds left), count random living enemies still carrying this script are possessed:
---      Attack -10 (until the end of the round), with the possession mark (value = damage).
--- At the start of round 3 only the damage of the round-2 possession is settled, then the script expires.
---
--- Parameters:
---   val    raw Dark damage per possessed stack at round end (computed from Spell Power at cast time)
---   count  number of stacks possessed per round
---   group  id of this cast (H7 audit A4: several casts are counted separately; carriers, this-round marks and possession marks are kept apart by id;
---          old saves without an id count as 0)

local KEY = "h7HauntingPlague"
local ROUND = "H7_HAUNT_ROUND_H7C"
local HAUNTED = "H7_HAUNTED_H7C"
local ANIM = "h7/fx/slHauntingPlague"
local SOUND = "h7/spell_haunting_plague_impact.ogg"

local function groupKey(group)
	if group == nil or group == 0 then return KEY end
	return KEY .. "#" .. tostring(group)
end

local function ownTriggers(unit, group)
	local want = groupKey(group)
	return unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b)
		return string.find(tostring(b:getSubtype() or ""), KEY, 1, true) ~= nil and b:getStacking() == want
	end)
end

local function turnsLeft(unit, group)
	local list = ownTriggers(unit, group)
	local t = 0
	for i = 1, list:size() do
		local r = list:getBonus(i):getTurnsRemain()
		if r > t then t = r end
	end
	return t
end

local function carrier(u, group)
	return u:isAlive() and not u:isGhost() and ownTriggers(u, group):size() > 0
end

local function byStacking(u, t, st)
	return u:getBonuses({ type = t }):filter(function(b) return b:getStacking() == st end)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	local group = self.group or 0
	if not carrier(unit, group) then return end
	local roundKey = "h7HauntRound#" .. tostring(group)
	local hauntKey = "h7HauntedMark#" .. tostring(group)
	if byStacking(unit, ROUND, roundKey):size() > 0 then return end

	local carriers = battle:getUnitsIf(function(u) return carrier(u, group) end)
	for _, u in ipairs(carriers) do
		server:addUnitBonus(battle, u, {
			type = ROUND, val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(), hidden = true,
			stacking = roundKey
		}, false)
	end

	-- 1. Stacks possessed last round (by this cast) take damage
	local haunted = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and byStacking(u, HAUNTED, hauntKey):size() > 0
	end)
	for _, u in ipairs(haunted) do
		local marks = byStacking(u, HAUNTED, hauntKey)
		local raw = 0
		for i = 1, marks:size() do raw = math.max(raw, marks:getBonus(i):getVal()) end
		server:removeUnitBonuses(battle, u, marks)
		local dmg = L.resist(u, raw, "darkSchool", KEY)
		if dmg > 0 and not u:isInvincible() then
			L.anim(server, battle, { u }, ANIM, "", 0.9)
			local done, killed = server:damageUnit(battle, u, dmg)
			server:appendLog(battle, {
				append         = { "core.bonus.H7_SL_LOG_H7C.description.7" },
				replaceStrings = { u:getCreature():getNameTextID(u:getCount()) },
				replaceNumbers = { done }
			})
			L.perishLog(server, battle, u, killed)
		end
	end

	-- 2. First two rounds: pick new stacks to possess
	if turnsLeft(unit, group) < 2 then return end
	local pool = battle:getUnitsIf(function(u)
		return carrier(u, group) and not u:isTurret() and not L.has(u, "SIEGE_WEAPON") and not u:isInvincible()
	end)
	local n = math.min(self.count or 2, #pool)
	local chosen = {}
	for _ = 1, n do
		local i = server:rngInt(1, #pool)
		chosen[#chosen + 1] = table.remove(pool, i)
	end
	if #chosen == 0 then return end
	L.anim(server, battle, chosen, ANIM, SOUND, 0.9)
	for _, u in ipairs(chosen) do
		server:addUnitBonus(battle, u, {
			type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = -10,
			duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(),
			stacking = "h7Haunted"
		}, false)
		server:addUnitBonus(battle, u, {
			type = HAUNTED, val = self.val or 0, duration = ENUM.BonusDuration.nTurns, turns = 2,
			sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(),
			stacking = hauntKey
		}, false)
		server:appendLog(battle, {
			append         = { "core.bonus.H7_SL_LOG_H7C.description.8" },
			replaceStrings = { u:getCreature():getNameTextID(u:getCount()) }
		})
	end
	server:refreshBattleUnits(battle)
end

return Script
