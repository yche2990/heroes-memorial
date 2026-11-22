local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local BattleLog = require("battleLog")
local L = require("combat/h5B3Lib")
local DATA = require("combat/h5DemonRageData")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Blood Rage, done as in the original (Yu's decision, round 235). Separate from Tears of Ashan's 15-level Blood Rage.
---
--- Orc stacks with Blood Rage (mark H5_DEMON_RAGED_H5C) pass this script to the whole battlefield (BATTLE_WIDE, one per stacking group),
--- every stack carries it: events on a stack only change its own rage; when a stack dies, the dead one gives rage to all Blood Rage stacks on the field.
---
--- Rage (original DefaultStats.xdb DemonRage, data in h5DemonRageData.lua):
---   melee attack +100, shot +50, casting on an enemy +40, sacrificing/devouring a goblin +60, hit by negative magic +10 (Confusion -15),
---   battle cry +10+10 x battle cry level, own stack dies +30 (+60 with Enrage), enemy stack dies +20,
---   defend -30, wait -100, each action while controlled by the Puppet Master -50, hit by life drain or weakening strike -90, skipping a turn while blind -100;
---   stun, Sniper's Arrow, intimidation, Bear Claw sweep (-20) and cowardly fleeing, being frightened (-100) notify this script by attaching H5_RAGE_EVENT_H5C from those scripts.
---   Rage gained while berserk (attacking the nearest stack) is doubled. Bad morale -80 has no event to hook, not done.
--- Levels: 200/500/1000 points for level 1/2/3, levels drop again when rage falls; each level's rewards add up and differ per creature (data table).
--- The maximum level depends on the hero's Blood Rage skill: Basic level 1, Advanced level 2, Expert level 3 (in the original only Barbarians have this skill).
---   The skill level is read from H5_RAGE_SKILL_H5C (the mark this mod adds to Tears of Ashan's "Blood Rage" skill); if absent, from the Tears of Ashan skill's own
---   RAGE_LEVEL_COUNTER cap (5/10/15 -> 1/2/3). Stacks of a hero without the skill (or without a hero) gain no rage.
--- Rage absorbs damage: when attacked, 50%/55%/60% of the damage is absorbed by skill level, each point absorbed costing 1200/health per creature rage,
---   absorbing only what the rage can cover when short. Spell damage is not absorbed (attacks only).

local RP = DATA.RP
local ABSORB_STACK = "h5RageAbsorb"
local LV_PREFIX = "h5RageLv_"
-- Original DemonRage1-3.(SpellVisual): by rage level
local ANIMATION = { "h5/fx/Spells_Warcry_Call_of_Blood_Call_of_Blood_Effect", "h5/fx/Spells_Warcry_Call_of_Blood_Call_of_Blood_2_Effect", "h5/fx/Spells_Warcry_Call_of_Blood_Call_of_Blood_3_Effect" }
local SOUND = "BLOODLUS"

local function isRaged(unit)
	return unit ~= nil and unit:hasBonuses({ type = "H5_DEMON_RAGED_H5C" })
end

--- Hero Blood Rage skill level 0-4
local function skillLevel(unit)
	local v = L.value(unit, { type = "H5_RAGE_SKILL_H5C" })
	if v > 0 then return math.min(v, 4) end
	local list = L.bonuses(unit, { type = "tears-of-ashan:RAGE_LEVEL_COUNTER" }) or L.bonuses(unit, { type = "RAGE_LEVEL_COUNTER" })
	if list == nil then return 0 end
	local cap = 0
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if b:getValType() == ENUM.BonusValueType.independentMin and b:getSource() == ENUM.BonusSource.secondarySkill then
			cap = math.max(cap, b:getVal())
		end
	end
	return math.min(3, math.floor((cap + 4) / 5))
end

local function maxLevel(unit)
	return math.min(3, skillLevel(unit))
end

local function rageOf(unit)
	return unit:getBonusesValue({ type = "H5_RAGE_POINTS_H5C" })
end

local function levelFor(points, cap)
	local lv = 0
	if points >= RP.RPForLevel1 then lv = 1 end
	if points >= RP.RPForLevel2 then lv = 2 end
	if points >= RP.RPForLevel3 then lv = 3 end
	return math.min(lv, cap)
end

local function source(unit)
	return unit:getCreature():getJsonKey()
end

local function info(unit)
	-- Shrunk and downgraded copies are looked up by source creature (h5Common.sourceKey)
	return DATA.CREATURES[L.unitShortKey(unit)]
end

local function shownLevel(unit)
	local v = unit:getBonusesValue({ type = "H5_BLOOD_RAGE_H5C" })
	return v % 10
end

local function setPoints(server, battle, unit, points)
	server:removeUnitBonuses(battle, unit, unit:getBonuses({ type = "H5_RAGE_POINTS_H5C" }))
	server:addUnitBonus(battle, unit, {
		type = "H5_RAGE_POINTS_H5C", val = points, valueType = ENUM.BonusValueType.baseNumber,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = source(unit),
		stacking = "h5RagePoints"
	}, false)
end

local function levelBonuses(unit)
	return unit:getBonuses({ sourceType = ENUM.BonusSource.other }):filter(function(b)
		return string.sub(b:getStacking(), 1, #LV_PREFIX) == LV_PREFIX
	end)
end

local function hasFright(d)
	for _, lv in ipairs(d.levels or {}) do
		for _, e in ipairs(lv) do
			local sub = e.subtype or ""
			if sub:sub(-12) == "h5FrightAura" then return true end
		end
	end
	return false
end

local function applyLevel(server, battle, unit, level)
	local d = info(unit)
	if d == nil then return end
	local old = levelBonuses(unit)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if old:size() > 0 then Proxy.removeExact(server, battle, unit, old) end
	server:removeUnitBonuses(battle, unit, unit:getBonuses({ type = "H5_BLOOD_RAGE_H5C" }))

	local n = 0
	for lv = 1, level do
		for _, e in ipairs(d.levels[lv] or {}) do
			n = n + 1
			local desc = {}
			for k, v in pairs(e) do desc[k] = v end
			desc.duration = ENUM.BonusDuration.oneBattle
			desc.sourceType = ENUM.BonusSource.other
			desc.sourceID = source(unit)
			desc.stacking = LV_PREFIX .. n
			if desc.hidden == nil then desc.hidden = false end
			-- Combat-event abilities (Wound Strike, Purge, Fright Aura, Intimidating Attack, Shield Bash...) are hidden: their content is listed level by level by the display bonus H5_BLOOD_RAGE_H5C;
			-- if not hidden they would show an empty icon and empty description in the ability list (audit A-4, checklist section 10)
			if desc.type == "COMBAT_EVENT_TRIGGER" then desc.hidden = true end
			server:addUnitBonus(battle, unit, desc, true)
		end
	end
	-- Fright Aura appears and disappears with the rage level: recalculated right after a level change, and the morale debuff on enemies is removed on dropping a level (audit A-5)
	if hasFright(d) then require("heroes-memorial.h5:combat/h5FrightAura").refresh(server, battle) end
	server:addUnitBonus(battle, unit, {
		type = "H5_BLOOD_RAGE_H5C", val = d.idx * 10 + level, valueType = ENUM.BonusValueType.baseNumber,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = source(unit),
		stacking = "h5RageShow"
	}, false)
end

--- Add or remove rage (delta may be negative), swapping rewards when the level changes
local function addRage(server, battle, unit, delta)
	if delta == 0 or unit == nil or not unit:isAlive() or not isRaged(unit) then return end
	local cap = maxLevel(unit)
	if cap <= 0 then return end
	if delta > 0 and unit:hasBonuses({ type = "ATTACKS_NEAREST_CREATURE" }) then
		delta = delta * RP.RPCoefUnderBerserk
	end
	local before = rageOf(unit)
	local points = math.max(0, before + delta)
	if points == before then return end
	setPoints(server, battle, unit, points)

	local level = levelFor(points, cap)
	local shown = shownLevel(unit)
	if level ~= shown then
		applyLevel(server, battle, unit, level)
		if level > shown then
			server:showBattleAnimation(battle, { { unit = unit } }, ANIMATION[math.max(1, math.min(3, level))], SOUND, 0.8, true)
			server:refreshBattleUnits(battle)
			server:appendLog(battle, {
				append = { "core.bonus.H5_RAGE_LOG_H5C.description.1" },
				replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
				replaceNumbers = { level }
			})
		end
	end
end

--- Rage events attached by other scripts (H5_RAGE_EVENT_H5C, value = rage change)
local function consumeEvents(server, battle, unit)
	if not unit:isAlive() then return end
	local list = unit:getBonuses({ type = "H5_RAGE_EVENT_H5C" })
	if list:size() == 0 then return end
	local sum = 0
	for i = 1, list:size() do sum = sum + list:getBonus(i):getVal() end
	server:removeUnitBonuses(battle, unit, list)
	addRage(server, battle, unit, sum)
end

local function hasScript(unit, name)
	return L.has(unit, { type = "COMBAT_EVENT_TRIGGER", subtype = name })
		or L.has(unit, { type = "COMBAT_EVENT_TRIGGER", subtype = "core:" .. name })
		or L.has(unit, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h5:" .. name })
end

local function isWarcry(spell)
	for _, school in ipairs(spell:getSchools() or {}) do
		local k = school:getJsonKey()
		if string.find(k, "warcries", 1, true) then return true end
	end
	return false
end

local GOBLIN_USE = { SacrificeGoblin = true, SwallowGoblin = true, h47Sacrifice = true, h47Devour = true }

local function usesGoblin(spell)
	local k = spell:getJsonKey()
	for name in pairs(GOBLIN_USE) do
		if string.find(k, name, 1, true) then return true end
	end
	return false
end

-- Battle start: rage stacks with the skill show 0 points, level 0
function Script:onBattleStart(server, battle, unit, other, payload)
	if not unit:isAlive() or not isRaged(unit) then return end
	if maxLevel(unit) <= 0 then return end
	if unit:getBonuses({ type = "H5_RAGE_POINTS_H5C" }):size() == 0 then
		setPoints(server, battle, unit, 0)
		applyLevel(server, battle, unit, 0)
		-- Starting rage (Memorial Shrine: Absolute Rage: H5_RAGE_START_H5C, original AbsoluteRageRP 500)
		local start = L.value(unit, { type = "H5_RAGE_START_H5C" })
		if start > 0 then addRage(server, battle, unit, start) end
	end
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or not isRaged(unit) then return end
	consumeEvents(server, battle, unit)
	-- Rounds blind (unable to act)
	if unit:hasBonuses({ type = "NOT_ACTIVE" }) then
		addRage(server, battle, unit, RP.BlindedRPPerTurn)
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not isRaged(unit) or not unit:isAlive() then return end
	if payload.isCounter or (payload.attackIndex or 0) > 0 then return end
	addRage(server, battle, unit, payload.ranged and RP.RangedAttackRP or RP.MeleeAtackRP)
end

function Script:onWait(server, battle, unit, other, payload)
	if isRaged(unit) then addRage(server, battle, unit, RP.WaitRP) end
end

function Script:onDefend(server, battle, unit, other, payload)
	if isRaged(unit) then addRage(server, battle, unit, RP.DefendRP) end
end

function Script:onUnitSpellcast(server, battle, unit, other, payload)
	if not isRaged(unit) or payload.spell == nil then return end
	if usesGoblin(payload.spell) then
		addRage(server, battle, unit, RP.UseGoblinRP)
		return
	end
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and battle:isHostile(unit, t.unit) then
			addRage(server, battle, unit, RP.CastSpellRP)
			return
		end
	end
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if not isRaged(unit) or not unit:isAlive() or payload.spell == nil then return end
	local spell = payload.spell
	if isWarcry(spell) then
		local lv = DATA.WARCRY[spell:getJsonKey()] or 1
		addRage(server, battle, unit, 10 + 10 * lv)
	elseif spell:isNegative() then
		if string.find(string.lower(spell:getJsonKey()), "forget", 1, true) then
			addRage(server, battle, unit, RP.ForgetfullnessRPBonusBase + RP.ForgetfullnessRPBonusPerTrained * 2)
		else
			addRage(server, battle, unit, RP.ReceiveCurseRP)
		end
	end
end

--- Stack dies: the dead one gives rage to all Blood Rage stacks on the field (clones and summoned copies do not count)
function Script:onDeath(server, battle, unit, other, payload)
	if unit:isClone() then return end
	local side = unit:getSide()
	local deadId = unit:unitID()
	local raged = battle:getUnitsIf(function(u)
		return u:unitID() ~= deadId and u:isAlive() and isRaged(u)
	end)
	for _, u in ipairs(raged) do
		if u:getSide() == side then
			local d = info(u)
			addRage(server, battle, u, (d and d.enraged) and RP.FriendlyStackKilledRPEnraged or RP.FriendlyStackKilledRP)
		else
			addRage(server, battle, u, RP.EnemyStackKilledRP)
		end
	end
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if not isRaged(unit) or not unit:isAlive() then return end
	consumeEvents(server, battle, unit)
	if other ~= nil and other:unitID() == unit:unitID() and unit:hasBonuses({ type = "HYPNOTIZED" }) then
		addRage(server, battle, unit, RP.ActionRPUnderHypnotize)
	end
end

---------------------------------------------------------------------------------------------------
-- Rage absorbing damage
---------------------------------------------------------------------------------------------------

local function absorbReductions(unit)
	return unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", sourceType = ENUM.BonusSource.other }):filter(function(b)
		return b:getStacking() == ABSORB_STACK
	end)
end

local function otherReduction(unit)
	return unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
		return b:getStacking() ~= ABSORB_STACK and b:getSource() ~= ENUM.BonusSource.spellEffect
	end):totalValue()
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	local old = absorbReductions(unit)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if old:size() > 0 then Proxy.removeExact(server, battle, unit, old) end
	if not unit:isAlive() or not isRaged(unit) then return end
	local skill = skillLevel(unit)
	if skill <= 0 or rageOf(unit) <= 0 then return end
	local pct = DATA.ABSORB[math.min(skill, 4) + 1] or 0
	local rest = otherReduction(unit)
	pct = math.min(pct, 95 - rest)
	if pct <= 0 then return end
	server:addUnitBonus(battle, unit, {
		type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = pct,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source(unit),
		stacking = ABSORB_STACK, hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local mine = absorbReductions(unit)
	if mine:size() > 0 then
		local pct = mine:getBonus(1):getVal()
		-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
		Proxy.removeExact(server, battle, unit, mine)
		local entry = self:ownEntry(unit, payload)
		local dealt = entry and entry.damage or 0
		local denom = 100 - otherReduction(unit) - pct
		if dealt > 0 and denom > 0 and isRaged(unit) then
			local absorbed = math.floor(dealt * pct / denom + 0.5)
			local hp = math.max(1, unit:getMaxHealth())
			local points = rageOf(unit)
			local cost = math.ceil(RP.HealthToRageTransferCoef * absorbed / hp)
			local overflow = 0
			if cost > points then
				local covered = math.floor(points * hp / RP.HealthToRageTransferCoef)
				overflow = absorbed - covered
				absorbed = covered
				cost = points
			end
			addRage(server, battle, unit, -cost)
			if absorbed > 0 then
				server:appendLog(battle, {
					append = { "core.bonus.H5_RAGE_LOG_H5C.description.2" },
					replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
					replaceNumbers = { absorbed }
				})
			end
			if overflow > 0 and unit:isAlive() and not unit:isInvincible() then
				local done, killed = server:damageUnit(battle, unit, overflow)
				BattleLog.creaturesPerish(server, battle, unit, killed)
			end
		end
	end

	if not unit:isAlive() or not isRaged(unit) or other == nil then return end
	-- Hit by life drain or weakening strike
	if hasScript(other, "lifeDrain") or hasScript(other, "h5WeakeningStrike") then
		addRage(server, battle, unit, RP.LifeDrainedRP)
	end
end

return Script
