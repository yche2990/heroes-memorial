local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local F = require("combat/h6FormSwap")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Sun Steed (H6 Sun Crusader SunStallion; made into a form change as in the original in round 360)
---
--- Original: cast on itself without using its action, it turns into light form (model SunRider_upg_ghost) for 1 round, passing over all obstacles,
--- unaffected by movement reduction, cooldown 3 rounds. Here: the original stack is hidden and replaced in place by the light-form Sun Crusader to (temporary stack),
--- changing back at the start of the next round (see combat/h6FormSwap, combat/h6SunSteedForm). The light-form stack is newly on the field
--- and has not acted this round, so it can act in light form right after casting (equivalent to "does not use its action").
--- Parameters: to (light-form creature), startA / startB (two parts of the transformation effect, each with R and L facings), sound

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

local function facing(unit)
	return unit:getSide() == ENUM.BattleSide.attacker and "R" or "L"
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local O = mechanics:getUnitCaster()
	local to = LIBRARY:getCreatureByName(self.to)
	if O == nil or not O:isAlive() or to == nil then return end
	if not server:describeChanges() then
		-- AI simulation: swapping stacks cannot be valued on the imaginary battlefield, so it is estimated as the old "flying this round"
		L.addBonus(server, battle, O, { type = "FLYING", duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = "h6SunSteedTrial" })
		L.useCast(server, battle, O, "h6AbSunSteed", nil)
		return
	end
	local hex = O:getPosition()
	local health = O:getAvailableHealth()
	local carry = F.snapshotFor(O)
	local dir = facing(O)
	-- Round 419: the hit before leaving (not deferred) plays first, then the original is hidden (checklist: let the stack leave only after the animation)
	if self.startA then
		server:showBattleAnimation(battle, { { hex = hex } }, self.startA .. dir, self.sound or "", 1.0, false)
	end
	F.hide(server, battle, O)
	local G = server:addUnit(battle, { count = O:getCount(), type = to, side = O:getSide(), position = hex, summoned = true })
	if G == nil then
		-- Light-form stack could not be added (should never happen): put the original back
		F.restore(server, battle, O, hex, health)
		return
	end
	-- Copy bonuses first (the health bonus from creature experience raises health per creature), then align total health with the original stack
	F.copyTo(server, battle, G, carry)
	local cur = G:getAvailableHealth()
	if cur > health then
		local st = G:copy(); st:damage(cur - health); server:changeUnit(battle, st, 0)
	end
	L.setMark(server, battle, G, F.LINK, O:unitID())
	-- Unlimited (only limited by the cooldown): refund this cast (as other active abilities)
	L.useCast(server, battle, O, "h6AbSunSteed", nil)
	-- The cooldown sits on the original stack (the light form lacks this ability; the cooldown continues after changing back)
	L.removeByStacking(server, battle, O, "H6_COOLDOWN_H6C", "h6Cooldown")
	L.addBonus(server, battle, O, {
		type = "H6_COOLDOWN_H6C", val = self.cooldown or 3,
		duration = ENUM.BonusDuration.nTurns, turns = (self.cooldown or 3) + 1,
		sourceType = ENUM.BonusSource.other, stacking = "h6Cooldown"
	}, false)
	if self.startB then
		server:showBattleAnimation(battle, { { unit = G } }, self.startB .. dir, "", 1.0, true)
	end
	server:refreshBattleUnits(battle)
	L.log(server, battle, "H6_SUN_STEED_H6C", 1, { L.name(G) }, {})
end

return Script
