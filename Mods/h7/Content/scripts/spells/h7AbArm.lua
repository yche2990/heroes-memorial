local Base = require("spells/spellEffect")
local L = require("spells/h7abLib")
local Proxy = require("lib/kadAiProxy")   -- AI simulation branch (ai-skills-design, as round 352)
local AI = require("spells/h7AiTrial")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Active abilities of H7 creatures that "change the next attack" (batch E): Magic Nova, Scatter Shot, Hammer Throw, Leaf Blade, Implosion Arrow, Ink Spray, Crippling Sting.
---
--- Cast on itself (spell NO_TARGET + canCastWithoutSkip, does not end the turn; previously canCastOnlyOnSelf, which the AI could not target, so changed to NO_TARGET), giving itself a "prepared" mark mark,
--- lasting until the end of this attack (counterattacks included), at the latest the end of this round (untilAfterAttackSequence + nTurns 1); if an enemy attacks it before it attacks,
--- the mark is removed before the hit (combat/h7StatusTick), so counterattacks do not get the prepared effect.
--- The actual effects come from bonuses on the creature with HAS_ANOTHER_BONUS_LIMITER (requiring mark) (SPELL_LIKE_ATTACK area shots, attack bonuses,
--- no range penalty, damage -x%...), or are settled by combat event scripts after the attack by mark (Implosion Arrow, Ink Spray, Crippling Sting).
--- Lua cannot make a stack attack, so as with the Sanctuary Kappa jump (round 298) it is split into "prepare" and "attack": after preparing, the player clicks a target to shoot / attack,
--- and that attack is a normal engine attack (damage, animation, projectile and counterattack as usual).
---
--- Parameters:
---   mark       mark bonus type (custom type with description and icon, shown in the stack's ability panel)
---   icon       icon of the mark (runtime bonuses must set their own icon)
---   animation  animation played on itself (optional), sound
---   log        battle log index (valueDescriptions of H7_ABE_LOG_H7C, "%s...")

function Script:applicableGeneral(mechanics, problem)
	if mechanics:getUnitCaster() == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local caster = mechanics:getUnitCaster()
	-- The spell is NO_TARGET (on itself, no target to click; as H5's h5AbSelfBuff): the effect only lands on the casting stack, the target is irrelevant.
	-- The client (casting as soon as the ability is selected) and the AI (BattleAI tries only one empty target for NO_TARGET) send an "empty destination" (no stack, invalid hex),
	-- and the engine also adds an empty destination when the target is empty; previously only "no destination / itself / its own hex" were accepted, so the empty destination was refused and neither players nor the AI could use it (review R1).
	-- So any destination is accepted (as the engine's NO_TARGET hero spells).
	if caster ~= nil then return true end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end

	-- AI simulation branch: the mark is worth 0 in the AI's estimate, so the extra value of "the attack after preparing" over a normal attack is reported instead (see spells/h7AiTrial)
	if Proxy.trial(server) then
		AI.arm(server, battle, caster, self.mark)
		return
	end

	L.removeByStacking(server, battle, caster, self.mark, "h7AbArm")
	L.addBonus(server, battle, caster, {
		type     = self.mark,
		val      = 1,
		duration = { "untilAfterAttackSequence", "nTurns" },
		turns    = 1,
		stacking = "h7AbArm",
		hidden   = false,
		icon     = self.icon
	})
	L.markNoSkip(server, battle, caster)
	L.armPending(server, battle, caster, self.mark) -- H7 audit 2a: refund the use when it went unused
	-- If, after preparing, it does not attack (waits, defends) and is then attacked by an enemy, counterattacks do not get the prepared effect: h7StatusTick removes the mark before the enemy's attack (review R1)
	L.ensureTracker(server, battle, caster)

	if server:describeChanges() then
		if self.animation then
			server:showBattleAnimation(battle, { { unit = caster } }, self.animation, self.sound or "", 1.0, true)
		end
		server:refreshBattleUnits(battle)
		if self.log then L.log(server, battle, self.log, { L.name(caster) }, {}) end
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
