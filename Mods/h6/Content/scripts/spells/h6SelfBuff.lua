local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Active abilities H6 creatures cast on themselves (spell target NO_TARGET):
---   the caster gets a bonus of bonusType (value val, subtype subtype) for turns rounds (1 = this round);
---   untilAttacked true: gone after being attacked once (Time Jump); untilAfterAttack true: gone after its own attack sequence (counterattacks included) (Feral Charge). A show bonus is added for display.
---   Sun Steed: FLYING; Time Jump: GENERAL_DAMAGE_REDUCTION 100; Life Drain: only the display bonus (the effect is read by h6LifeDrain).
--- Cannot be cast again while the ability's effect is on it (show, or bonusType without show).
--- If the spell has canCastWithoutSkip, the stack can still act after casting.
--- Parameters: bonusType, val, subtype, turns, untilAttacked, untilAfterAttack, show, key, uses (uses per battle, unlimited if omitted), animation, sound

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	local check = self.show or self.bonusType
	if check and caster:hasBonuses({ type = check }) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	return self:applicableGeneral(mechanics, problem)
end

local AI_ATTACK, AI_TURNS = 12, 8

--- For the AI simulation: whether casting this round is useful (only decides whether a proxy value is reported, real casts are unaffected)
---   Life Drain (H6_LIFE_DRAIN_H6C): there is a living enemy to hit and another wounded (or partly dead) friendly undead stack to heal;
---   Dark Purge (H6_PURGE_H6C): some enemy carries a beneficial spell that can be dispelled;
---   other mark-type effects: always useful.
function Script:worth(battle, caster)
	local mark = self.show or self.bonusType
	if mark == "H6_LIFE_DRAIN_H6C" then
		local prey = battle:getUnitsIf(function(u) return L.hostile(battle, caster, u) and L.isLiving(u) end)
		if #prey == 0 then return false end
		local hurt = battle:getUnitsIf(function(u)
			return u:isAlive() and not u:isGhost() and not u:isTurret() and u:unitID() ~= caster:unitID()
				and not battle:isHostile(caster, u) and L.isUndead(u) and u:getTotalHealth() > u:getAvailableHealth()
		end)
		return #hurt > 0
	elseif mark == "H6_PURGE_H6C" then
		local buffed = battle:getUnitsIf(function(u)
			if not L.hostile(battle, caster, u) then return false end
			return u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
				local sp = LIBRARY:getSpellByName(b:getSourceID())
				return sp ~= nil and sp:isPositive()
			end):size() > 0
		end)
		return #buffed > 0
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local turns = self.turns or 1
	local key = self.key or "h6SelfBuff"
	-- Round 419: mark-type effects (Life Drain, Dark Purge) are worth 0 in the AI simulation, so a native bonus is reported as well so the AI can see it.
	-- 2026-11-08: the engine's stack valuation (lib/battle/CombatValue.cpp) ignores GENERAL_DAMAGE_PREMY, so the old "damage +15%" was 0 to the AI;
	--   PRIMARY_SKILL attack, which the AI understands, is reported instead, and only when the ability is really useful this round (see Script:worth); otherwise the value is 0 and the AI does not cast.
	--   Values: Attack +AI_ATTACK reported for AI_TURNS rounds. The engine discounts by "remaining rounds / 8" (durationWeight / expiringSkill in CombatValue),
	--   so the earlier "+3 for 1 round" came to only +0.4 Attack, almost nothing; +12 for 8 rounds is not discounted, roughly +60% output and +25% stack value,
	--   and the AI casts it first when a normal attack is poor (out of reach, high enemy Defense, a counterattack to take). Both abilities still allow acting after casting (canCastWithoutSkip),
	--   but the AI ignores that flag and treats the action as used, so reporting generously costs nothing; frequency is held by the cooldown (2 / 3 rounds).
	--   Feral Charge (BLOCKS_RETALIATION) is itself a native bonus the AI understands and was already cast, so nothing extra is reported (the damage bonus reported before was worth 0, removing it changes nothing)
	if Proxy.trial(server) and (self.bonusType == nil or self.bonusType:sub(-4) == "_H6C") and self:worth(battle, caster) then
		Proxy.buff(server, battle, caster, { type = "PRIMARY_SKILL", subtype = "attack", val = AI_ATTACK, turns = AI_TURNS })
	end
	local duration = ENUM.BonusDuration.nTurns
	if self.untilAttacked then duration = duration + ENUM.BonusDuration.untilBeingAttacked end
	if self.untilAfterAttack then duration = duration + ENUM.BonusDuration.untilAfterAttackSequence end
	if self.bonusType then
		L.removeByStacking(server, battle, caster, self.bonusType, key)
		L.addBonus(server, battle, caster, { type = self.bonusType, subtype = self.subtype, val = self.val or 0, hidden = true,
			duration = duration, turns = turns, stacking = key }, false)
	end
	if self.show then
		L.removeByStacking(server, battle, caster, self.show, key)
		L.addBonus(server, battle, caster, { type = self.show, val = turns,
			duration = duration, turns = turns, stacking = key }, false)
	end
	if self.animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = caster } }, self.animation, self.sound or "", 1.0, true)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.useCast(server, battle, caster, key, self.uses)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
