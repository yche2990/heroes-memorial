local Base = require("spells/unitEffect")
local BattleLog = require("battleLog")
local L = require("spells/h5AbLib")
local C, A = L.C, L.A
local LEAP = "H5_LEAP_H5C"
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Active abilities of H5 creatures with movement (on a stack):
---   mode = "leap"     Leap (Horned Grunt): leaps next to an enemy minDist-maxDist hexes away (a normal move, charging straight there, with start/move/stop frames),
---                     and cannot move again this round after landing. Then the engine attacks normally (attack, hit and retaliation animations): hitting this enemy deals +perCell% damage per hex leapt,
---                     and its retaliation deals retaliate times damage (original 3 times). The bonuses are settled by damage/h5DamagePatch through the hidden mark H5_LEAP_H5C,
---                     only for the enemy leapt at, removed when this round's exchange or the round ends. Lua cannot make a stack attack, so like the Kappa of Yingzhou it is split into two steps, "leap" and "hit",
---                     and the spell itself does not end the turn (canCastWithoutSkip). Unlimited
---   mode = "harpoon"  Harpoon Strike (Harpooner): shoots an enemy stack (large ones too), pulls it one hex closer and deals normal shot damage. Unlimited
---   mode = "summon"   Teleport (Arch Devil): teleports any stack within movement range (ignoring obstacles; friend or foe) next to itself. Unlimited
--- Parameters: mode, minDist, maxDist, perCell, retaliate, uses, mark, hitAnimation, hitSound

local function speedOf(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "STACKS_SPEED" }) end)
	if ok and type(v) == "number" then return v end
	return 0
end

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) or not unit:isAlive() or unit:isTurret() then return false end
	if unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	local caster = mechanics:getUnitCaster()
	if caster == nil or unit:unitID() == caster:unitID() then return false end
	local d = C.unitDistance(caster, unit)
	if self.mode == "leap" then
		if not mechanics:getBattle():isHostile(caster, unit) then return false end
		if d < (self.minDist or 3) or d > (self.maxDist or 8) then return false end
		return L.freeHexNextTo(mechanics:getBattle(), caster, unit, caster:getPosition()) ~= nil
	elseif self.mode == "harpoon" then
		return mechanics:getBattle():isHostile(caster, unit)
	elseif self.mode == "summon" then
		if d <= 1 then return false end
		return d <= speedOf(caster) + 1
	end
	return false
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	return false
end

local function moveTo(server, battle, unit, hex)
	if hex == nil then return false end
	local ok = pcall(function() server:moveUnit(battle, unit, hex, true) end)
	return ok
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	local unit = dest and dest.unit
	if unit == nil or not unit:isAlive() then return end
	local mode = self.mode

	if mode == "leap" then
		local from = caster:getPosition()
		local hex = L.freeHexNextTo(battle, caster, unit, from)
		if hex == nil then return end
		local cells = C.hexDistance(from, hex)
		-- Round 344: AI simulation branch (ai-skills-design #28). Leap only moves the stack and also gives it Speed -100% (vetoed by the AI as an own loss).
		-- In the simulation it does not leap, but reports "the hit after landing": the target loses one attack x (1 + perCell% x hexes) x 0.9 - the loss from its retaliate-times retaliation (in its health).
		-- It can still act after leaping, and the AI attacks normally after landing. Real casts do not go through here
		if Proxy.trial(server) then
			local atk = Proxy.attackEstimate(caster, unit, 100 + (self.perCell or 10) * cells, false) * 0.9
			local back = Proxy.attackEstimate(unit, caster, 100 * (self.retaliate or 3), false) / caster:getMaxHealth()
			local hp = atk - Proxy.costHp(caster, math.min(back, caster:getCount()), unit)
			if hp >= unit:getMaxHealth() then Proxy.damage(server, battle, unit, hp) end
			return
		end
		-- Normal move (not a teleport): the client plays start, move and stop frames, the whole move taking the time of one hex, so it looks like a single dash
		local moved = pcall(function() server:moveUnit(battle, caster, hex, false) end)
		if not moved then moveTo(server, battle, caster, hex) end
		if server:describeChanges() and self.mark then L.log(server, battle, self.mark, 1, { C.name(caster), C.name(unit) }, {}) end

		-- Hidden mark until the end of this round's exchange (or the round), settled by the damage patch
		local untilHit = ENUM.BonusDuration.untilAfterAttackSequence + ENUM.BonusDuration.nTurns
		local function mark(stacking, val, extra)
			local old = caster:getBonuses({ type = LEAP }):filter(function(b) return b:getStacking() == stacking end)
			-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
			if old:size() > 0 then Proxy.removeExact(server, battle, caster, old) end
			local d = { type = LEAP, val = val, duration = untilHit, turns = 1, stacking = stacking, hidden = true,
				sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey() }
			for k, v in pairs(extra or {}) do d[k] = v end
			server:addUnitBonus(battle, caster, d, true)
		end
		mark("h5LeapTarget", unit:unitID() + 1)                                   -- The enemy leapt at (id + 1)
		mark("h5LeapBoost", (self.perCell or 10) * cells)                         -- Damage +% when hitting it
		mark("h5LeapBack", math.max(0, (self.retaliate or 3) - 1) * 100)          -- Damage +% for its retaliation (3 times = +200%)
		-- Cannot move again this round after landing, can only hit adjacent enemies
		local stop = caster:getBonuses({ type = "STACKS_SPEED" }):filter(function(b) return b:getStacking() == "h5LeapLanded" end)
		-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
		if stop:size() > 0 then Proxy.removeExact(server, battle, caster, stop) end
		server:addUnitBonus(battle, caster, {
			type = "STACKS_SPEED", val = -100, valueType = ENUM.BonusValueType.percentToAll,
			duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = "h5LeapLanded", hidden = true,
			sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey()
		}, true)
	elseif mode == "harpoon" then
		local dmg = A.attackDamage(server, caster, unit, 100, true)
		if server:describeChanges() and self.hitAnimation then server:showBattleAnimation(battle, { { unit = unit } }, self.hitAnimation, self.hitSound or "", 1.0, true) end
		local dealt, killed = server:damageUnit(battle, unit, dmg)
		if server:describeChanges() then
			BattleLog.creaturesPerish(server, battle, unit, killed)
			if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster), C.name(unit) }, { dealt }) end
		end
		if unit:isAlive() and not unit:hasBonuses({ type = "H5_HOLD_GROUND_H5C" }) and C.unitDistance(caster, unit) > 1 then
			-- Pulled one hex: pushing -1 hex toward the caster = the reverse of the direction "caster -> target"
			local hexes = C.hexTable(battle)
			local idx = C.lineIndex(unit:getPosition(), caster:getPosition(), 1)
			local h = idx and hexes[idx]
			if h ~= nil and battle:isAccessibleForUnit(unit, h) then moveTo(server, battle, unit, h) end
		end
	elseif mode == "summon" then
		local hex = L.freeHexNextTo(battle, unit, caster, unit:getPosition())
		if hex == nil then return end
		-- Round 344: AI simulation branch (ai-skills-design #3). Teleport only moves a stack, valued 0 by the AI. Reported instead as "the extra attack it allows":
		--   pulling in an own melee stack (with no enemy beside it yet, while the caster has enemies beside it): the most valuable enemy beside the caster loses 0.6 x one of its attacks;
		--   pulling in an enemy shooter (caster is melee): the shooter loses 0.5 x one of the caster's attacks + 0.25 x the value of one of its shots (cannot shoot while blocked).
		-- Real casts do not go through here
		if Proxy.trial(server) then
			if not battle:isHostile(caster, unit) then
				if unit:isShooter() then return end
				if #Proxy.adjacent(battle, unit, function(x) return Proxy.hostile(battle, unit, x) end) > 0 then return end
				local best, bestScore = nil, 0
				for _, e in ipairs(Proxy.adjacent(battle, caster, function(x) return Proxy.hostile(battle, caster, x) end)) do
					local s = Proxy.attackEstimate(unit, e, 100, false) / e:getMaxHealth() * Proxy.value(e)
					if s > bestScore then best, bestScore = e, s end
				end
				if best ~= nil then Proxy.damage(server, battle, best, 0.6 * Proxy.attackEstimate(unit, best, 100, false)) end
			elseif unit:isShooter() and not caster:isShooter() then
				local shot = Proxy.attackEstimate(unit, caster, 100, true)
				local hp = 0.5 * Proxy.attackEstimate(caster, unit, 100, false)
					+ Proxy.hpOf(0.25 * shot / caster:getMaxHealth() * Proxy.value(caster), unit)
				Proxy.damage(server, battle, unit, hp)
			end
			return
		end
		moveTo(server, battle, unit, hex)
		if server:describeChanges() then
			server:showBattleAnimation(battle, { { unit = unit } }, "h5/fx/Characters_Gating", "TELPTIN", 1.0, true)   -- SummonOtherEnd.(SpellVisual)
			server:refreshBattleUnits(battle)
			if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster), C.name(unit) }) end
		end
	end
	server:refreshBattleUnits(battle)
	L.useCast(server, battle, caster, "h5AbMove" .. (mode or ""), self.uses)
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
	function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
		return nil
	end
end

return Script
