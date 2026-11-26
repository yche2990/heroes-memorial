local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local F = require("combat/h6FormSwap")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Dual Form (H6 Fate Spinner, Fate Weaver)
---
--- Cast on itself: changes to the other form to (human <-> spider). From round 360b it works like the Sun Steed (combat/h6FormSwap):
---   the stack in the army at battle start (the original) is not removed when changing form, only hidden, and a temporary stack of the other form is added in its place; when changing back
---   the temporary stack is removed and the original put back. So creature experience, stack artifacts and the army slot are always kept, while spell effects,
---   ability uses and cooldowns go along, and count, total health and position stay the same. Losses of the temporary form are synced back to the original at once (combat/h6FormLink).
---   At battle end it is settled as the original stack: the army keeps the form it had at battle start (outside battle the form can be switched for free with "Upgrade" in the creature window).
--- The original forces "Wait" after changing form: the engine does not let scripts put a stack into the waiting state directly, so the new stack gets a hidden Speed -999
--- until its turn comes (STACK_GETS_TURN, removed automatically by the engine when its turn comes): it moves to the end of the stacks that have not acted this round,
--- and when its turn comes its speed is back, so movement is unaffected. The new form cannot change again for cooldown rounds.
--- Parameters: to, cooldown, animation, sound

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() or caster:isClone() or caster:isGhost() or LIBRARY:getCreatureByName(self.to) == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	return self:applicableGeneral(mechanics, problem)
end

--- For the AI simulation (2026-11-08): how much more changing form this round would achieve, converted to proxy damage on one enemy stack. Returns (enemy, health points), or nil when not worth changing.
--- Both forms have almost the same damage and attack (the spider form slightly higher); the difference is the fighting style: human form is melee (higher Defense; the Fate Weaver's human form also has Dance of Death), spider form is a shooter (lower Defense; the Fate Weaver's spider form also has Frozen Web).
--- Rules (the current form is judged by whether it has SHOOTER, not by ammunition):
---   Human -> spider: no adjacent enemy (a shooter will not be blocked) and no enemy reachable this round (nearest enemy distance - 1 > Speed).
---     Then the human form could only reposition, while the spider form (moved to the end of the round) can shoot once: value = expected damage of one shot, booked on the enemy most worth shooting.
---   Spider -> human: an enemy is adjacent (a blocked shooter can only make half-damage melee attacks); or out of arrows with an enemy reachable this round (the nearest one counts).
---     Value = 60% of the expected damage of one melee attack on the adjacent enemy most worth hitting (full human melee damage minus the spider form's blocked half damage, plus the human form's higher Defense);
---     for the Fate Weaver, +25% for each further adjacent enemy (the human form's Dance of Death hits all adjacent enemies), up to 3 stacks.
---   Nothing is reported otherwise (value 0, the AI does not change). The two directions exclude each other (adjacent enemy or not), so after changing it only changes back once the situation changes,
---   never back and forth every round; the 1-round cooldown also prevents that.
function Script:trialGain(battle, C)
	local ranged = C:hasBonuses({ type = "SHOOTER" })
	local adj = Proxy.adjacent(battle, C, function(u) return Proxy.hostile(battle, C, u) end)
	if not ranged then
		if #adj > 0 then return nil, 0 end
		local _, nd = Proxy.nearestHostile(battle, C)
		local ok, speed = pcall(function() return C:getBonusesValue({ type = "STACKS_SPEED" }) end)
		if not ok or type(speed) ~= "number" then speed = 0 end
		if nd - 1 <= speed then return nil, 0 end
		local best, bv, bhp = nil, 0, 0
		for _, e in ipairs(battle:getUnitsIf(function(u) return Proxy.hostile(battle, C, u) end)) do
			local hp = math.min(Proxy.attackEstimate(C, e, 100, false), e:getAvailableHealth())
			local v = hp / math.max(1, e:getMaxHealth()) * Proxy.value(e)
			if v > bv then best, bv, bhp = e, v, hp end
		end
		return best, bhp
	end
	local targets = adj
	if #targets == 0 then
		if C:isShooter() then return nil, 0 end
		-- Out of arrows: the spider form can only walk over for half-damage melee, the human form for full damage; the nearest enemy reachable this round counts
		local e, nd = Proxy.nearestHostile(battle, C)
		local ok, speed = pcall(function() return C:getBonusesValue({ type = "STACKS_SPEED" }) end)
		if not ok or type(speed) ~= "number" then speed = 0 end
		if e == nil or nd - 1 > speed then return nil, 0 end
		targets = { e }
	end
	local best, bv, bhp = nil, 0, 0
	for _, e in ipairs(targets) do
		local hp = math.min(Proxy.attackEstimate(C, e, 100, false), e:getAvailableHealth())
		local v = hp / math.max(1, e:getMaxHealth()) * Proxy.value(e)
		if v > bv then best, bv, bhp = e, v, hp end
	end
	local factor = 0.6
	if string.find(self.to or "", "FateWeaver", 1, true) and #adj > 1 then factor = factor + 0.25 * math.min(#adj - 1, 2) end
	return best, bhp * factor
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local C = mechanics:getUnitCaster()
	local to = LIBRARY:getCreatureByName(self.to)
	if C == nil or not C:isAlive() or to == nil then return end
	-- AI simulation: swapping stacks cannot be valued on the imaginary battlefield, so no real change happens (real casts work as usual).
	-- 2026-11-08 (Yu let the AI change form): a proxy value is reported instead (see Script:trialGain); the AI changes only when the other form is better
	if Proxy.trial(server) then
		local e, hp = self:trialGain(battle, C)
		if e ~= nil and hp > 0 then Proxy.damage(server, battle, e, hp) end
		L.useCast(server, battle, C, "h6DualForm", nil)
		return
	end
	if self.animation then
		server:showBattleAnimation(battle, { { unit = C } }, self.animation, self.sound or "", 1.0, false)
	end
	-- Does not use up casts (only limited by the cooldown): the original must be able to change again after changing out and back, so this cast is refunded
	L.useCast(server, battle, C, "h6DualForm", nil)
	local O = F.original(battle, C)
	local now
	if O ~= nil and O:getCreature():getJsonKey() == to:getJsonKey() then
		-- Temporary form back to the original stack
		F.swapBack(server, battle, C, O)
		now = O
	elseif O ~= nil then
		-- Temporary form into a third form (no such creature exists now): replace the temporary stack, the original stays hidden
		local carry = F.snapshotFor(C, { abilities = false, keepSlow = true })
		local pos, health = C:getPosition(), C:getAvailableHealth()
		server:removeUnit(battle, C)
		now = server:addUnit(battle, { count = O:getCount(), type = to, side = O:getSide(), position = pos, summoned = true })
		if now == nil then F.restore(server, battle, O, pos, health); return end
		F.copyTo(server, battle, now, carry)
		local cur = now:getAvailableHealth()
		if cur > health then local st = now:copy(); st:damage(cur - health); server:changeUnit(battle, st, 0) end
		L.setMark(server, battle, now, F.LINK, O:unitID())
	else
		-- Original stack changes out into a temporary form
		now = F.swapOut(server, battle, C, to, { abilities = false, keepSlow = true })
		if now == nil then return end
	end
	-- Counts as waiting: moved to the end of the round, removed automatically when its turn comes
	L.addBonus(server, battle, now, {
		type = "STACKS_SPEED", val = -999, hidden = true,
		duration = ENUM.BonusDuration.stackGetsTurn + ENUM.BonusDuration.nTurns, turns = 1, stacking = "h6DualFormWait"
	}, false)
	-- Cooldown on the new form
	L.removeByStacking(server, battle, now, "H6_COOLDOWN_H6C", "h6Cooldown")
	L.addBonus(server, battle, now, {
		type = "H6_COOLDOWN_H6C", val = self.cooldown or 1,
		duration = ENUM.BonusDuration.nTurns, turns = (self.cooldown or 1) + 1,
		sourceType = ENUM.BonusSource.other, stacking = "h6Cooldown"
	}, false)
	server:refreshBattleUnits(battle)
	L.log(server, battle, "H6_DUAL_FORM_H6C", 1, { L.name(now) }, {})
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
