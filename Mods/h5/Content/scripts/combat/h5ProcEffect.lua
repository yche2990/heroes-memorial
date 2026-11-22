local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local B3 = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5: special effects (not spells) applied by chance on attack
---
--- effect:
---   bash        Shield Bash: after a melee hit (attack and retaliation), the target cannot retaliate against this hit and its initiative is reset (it no longer acts this round if it had not). Mechanical units are unaffected
---   atbReset    Crushing Blow: initiative reset (retaliation unaffected)
---   fear        Intimidating Attack: the target flees to the battlefield edge away from the attacker, initiative reset. Mind-immune stacks are unaffected; judged on health after the hit
---   pushAtb     Bear Claw Sweep: the target is pushed back one hex and its initiative reset; the chance is also multiplied by "hexes moved this time / 2" (no trigger without moving, at most double)
---   atbDrop     Sniper's Arrow: the target's initiative drops by amount% (Speed -amount% until the end of the round)
---   extraAttack Assault: chance to attack twice. H5 rolls when striking; VCMI fixes the number of attacks before the strike, so at battle start and
---               after each of its own actions the chance for the next strike is rolled in advance (opponent unknown, equal health assumed); on success one extra attack is attached
--- Parameters: pf (trigger factor), melee, ranged, amount (atbDrop), perCell (pushAtb)

local function pending(effect) return "h5Pending:" .. effect end

local function canAffect(self, battle, unit, target)
	if target == nil or not target:isAlive() or target:isInvincible() then return false end
	if not battle:isHostile(unit, target) then return false end
	if target:hasBonuses({ type = "SIEGE_WEAPON" }) or target:isTurret() then return false end
	if self.effect == "bash" and (H5.isMechanical(target)) then return false end
	if self.effect == "fear" and H5.immuneToSpell(target, nil, { mind = true }) then return false end
	return true
end

-- ---- Assault: roll the next strike in advance ---------------------------------------------------------------

function Script:rollExtra(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "ADDITIONAL_ATTACK", "h5Brutality")
	if not unit:isAlive() then return end
	local chance = H5.procChance(unit, unit, self.pf or 1, unit:getAvailableHealth())
	if H5.roll(server, battle, unit, chance) then
		server:addUnitBonus(battle, unit, {
			type       = "ADDITIONAL_ATTACK",
			val        = 1,
			duration   = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other,
			sourceID   = unit:getCreature():getJsonKey(),
			stacking   = "h5Brutality",
			hidden     = true
		}, false)
	end
end

function Script:onBattleStart(server, battle, unit, other)
	if self.effect == "extraAttack" then self:rollExtra(server, battle, unit) end
end

-- ---- Move distance (Bear Claw Sweep) ------------------------------------------------------------------

function Script:onBeforeMove(server, battle, unit, other, payload)
	if self.effect == "pushAtb" then H5.recordMoveStart(server, battle, unit) end
end

function Script:onAfterMove(server, battle, unit, other, payload)
	if self.effect == "pushAtb" then H5.recordMoveEnd(server, battle, unit) end
end

-- ---- Checks after a hit -----------------------------------------------------------------------------

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	if self.effect == "extraAttack" then return end
	if payload.ranged then
		if self.ranged == false then return end
	else
		if self.melee == false then return end
	end
	-- Only Shield Bash counts retaliations too
	if payload.isCounter and self.effect ~= "bash" then return end

	local entry = H5.firstTarget(payload)
	if entry == nil then return end
	local target = entry.unit
	if not canAffect(self, battle, unit, target) then return end
	if (entry.damage or 0) <= 0 then return end

	local defHealth = entry.healthBeforeAttack
	if self.effect == "fear" then defHealth = target:getAvailableHealth() end
	local chance = H5.procChance(unit, target, self.pf or 1, defHealth)
	if self.effect == "pushAtb" then
		local cells = H5.movedCells(unit)
		if cells <= 0 then return end
		chance = math.min(100, math.floor(chance * math.min(cells, 4) / 2 + 0.5))
	end
	if not H5.roll(server, battle, unit, chance) then return end

	local name = H5.name(target)
	if self.effect == "bash" then
		-- The retaliation check for this hit comes after this event: attach "cannot retaliate", removed at the end of its own action
		server:addUnitBonus(battle, target, {
			type = "NO_RETALIATION", val = 0,
			duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
			stacking = "h5BashNoRet", hidden = true
		}, false)
		H5.setMark(server, battle, target, "h5Bashed", unit:unitID() + 1, 1)
		H5.resetAtb(server, battle, target)
		B3.rageEvent(server, battle, target, -20)
		server:showBattleAnimation(battle, { { unit = target } }, "h5/fx/Characters_ShieldBash", "", 0.7, true)   -- RPGRoot SHIELD_BASH
		server:refreshBattleUnits(battle)
		H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.1", { name }, {})
	elseif self.effect == "atbReset" then
		H5.resetAtb(server, battle, target)
		server:refreshBattleUnits(battle)
		H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.2", { name }, {})
	elseif self.effect == "atbDrop" then
		H5.slowNextTurn(server, battle, target, self.amount or 20, 1, unit:getCreature():getJsonKey(), "h5WardingArrows")
		B3.rageEvent(server, battle, target, -20)
		server:refreshBattleUnits(battle)
		H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.3", { name }, {})
	elseif self.effect == "fear" or self.effect == "pushAtb" then
		-- Pushes and fleeing are done after the whole action ends
		H5.setMark(server, battle, target, pending(self.effect), unit:unitID() + 1, 1)
	end
end

--- Intimidation: find the farthest free hex on its own side at least dist hexes from the attacker (runs at most 8 hexes)
local function fleeHex(battle, target, attacker)
	local hexes = battle:getAllPossibleHexes()
	local best, bestScore = nil, -1
	local from = target:getPosition()
	for i = 1, hexes:size() do
		local h = hexes:at(i)
		local ok, acc = pcall(function() return battle:isAccessibleForUnit(target, h) end)
		if ok and acc and H5.hexDistance(from, h) <= 8 then
			local score = H5.unitHexDistance(attacker, h) * 10
			-- Toward the edge on its own side
			if target:getSide() == ENUM.BattleSide.attacker then
				score = score + (15 - h:getX())
			else
				score = score + h:getX()
			end
			if score > bestScore then best, bestScore = h, score end
		end
	end
	return best
end

function Script:onActionFinished(server, battle, unit, other, payload)
	-- Shield Bash may happen on a retaliation: whoever's action it is, the "cannot retaliate" attached by this stack is removed when the action ends
	if self.effect == "bash" then
		local victims = battle:getUnitsIf(function(o)
			return o:isAlive() and H5.markValue(o, "h5Bashed") == unit:unitID() + 1
		end)
		for _, v in ipairs(victims) do
			H5.removeByStacking(server, battle, v, "NO_RETALIATION", "h5BashNoRet")
			H5.clearMark(server, battle, v, "h5Bashed")
		end
		return
	end
	if other == nil or other:unitID() ~= unit:unitID() then return end

	if self.effect == "extraAttack" then
		self:rollExtra(server, battle, unit)
		return
	end
	if self.effect == "pushAtb" then H5.clearMove(server, battle, unit) end

	if self.effect ~= "fear" and self.effect ~= "pushAtb" then return end
	local key = pending(self.effect)
	local victims = battle:getUnitsIf(function(o)
		return H5.markValue(o, key) == unit:unitID() + 1
	end)
	for _, v in ipairs(victims) do
		H5.clearMark(server, battle, v, key)
		if v:isAlive() and not v:isGhost() then
			local dest = nil
			if self.effect == "fear" then
				dest = fleeHex(battle, v, unit)
			elseif not v:hasBonuses({ type = "H5_HOLD_GROUND_H5C" }) then
				dest = H5.pushHex(battle, unit:getPosition(), v, 1)
			end
			if dest ~= nil then
				if self.effect == "fear" then server:showBattleAnimation(battle, { { unit = v } }, "h5/fx/Characters_Fear", "", 0.7, true) end
				server:moveUnit(battle, v, dest, true)
			end
			H5.resetAtb(server, battle, v)
			B3.rageEvent(server, battle, v, -20)
			server:refreshBattleUnits(battle)
			H5.log(server, battle, "core.bonus.H5_MARK_H5C.description." .. (self.effect == "fear" and "4" or "5"), { H5.name(v) }, {})
		end
	end
end

return Script
