local Base = require("spells/spellEffect")
local L = require("spells/h5AbLib")
local C = L.C
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Active abilities H5 creatures cast on themselves:
---   kind = "dash"        Dash (Rakshasa): Speed +pct% (H5: initiative x2) for turns rounds
---   kind = "forestRage"  Forest Rage (Savage Treant): Defense halved, the lost Defense added to Attack; Speed +pct%; no longer entangles enemies; until the battle ends (once per battle)
---   kind = "flamestrike" Flamestrike (Warlord): next attack +pct% damage and puts Mark of Fire (spell) on the target; it can still act after casting (once per battle)
---   kind = "powerFeed"   Power Feed (Greater Druid): own hero's Spell Power + this stack's creature spell power, until the battle ends or this stack dies; only one stack per side can link
---   kind = "invisible"   Invisibility (Shadow Mistress, Stalker): for turns rounds it cannot be attacked or targeted by magic (INVINCIBLE), and targets of its attacks cannot retaliate;
---                        revealed after it attacks once (when this round's exchange ends); revealScript is attached, revealing it when enemies are adjacent
--- Parameters: kind, pct, turns, spell, uses (per battle, unlimited if omitted), show (display bonus type), mark (bonus name for the battle log),
---       revealScript, revealMark (for invisibility)

local STACK = "h5AbSelfBuff"

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	if self.kind == "powerFeed" then
		local others = mechanics:getBattle():getUnitsIf(function(u)
			return u:isAlive() and not mechanics:getBattle():isHostile(caster, u) and u:hasBonuses({ type = self.show })
		end)
		if #others > 0 then
			problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
			return false
		end
	end
	return true
end

function Script:add(server, battle, unit, desc)
	desc.stacking = desc.stacking or (STACK .. (self.kind or ""))
	L.addBonus(server, battle, unit, desc, true)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local kind = self.kind
	local logNumbers = {}

	-- Round 344: AI simulation branch (ai-skills-design #13 Invisibility). INVINCIBLE is worth 0 in the AI's estimate, so "damage avoided" is reported instead =
	-- expected damage from enemies able to reach it this round x 0.5, booked as value, then the native "no retaliation for this hit" is attached.
	-- Not used when already invisible, enemies are adjacent (it would be revealed at once), or less than one creature's worth is avoided (prevents going invisible every round without attacking). Real casts do not go through here
	-- Round 344: Power Feed (ai-skills-design #45): adds Spell Power to the own hero, which the AI's creature cast estimate cannot see.
	-- The simulation books "stack value x 2%", capped as a weak ability; not used when the side already has a link. Real casts do not go through here
	if kind == "powerFeed" and Proxy.trial(server) then
		if #battle:getUnitsIf(function(u) return not battle:isHostile(caster, u) and self.show and u:hasBonuses({ type = self.show }) end) > 0 then return end
		local e = Proxy.nearestHostile(battle, caster)
		if e == nil then return end
		local hp = Proxy.capWeak(Proxy.hpOf(Proxy.value(caster) * caster:getCount() * 0.02, e), battle, caster, e)
		if hp >= e:getMaxHealth() then Proxy.damage(server, battle, e, hp) end
		return
	end

	if kind == "invisible" and Proxy.trial(server) then
		if caster:hasBonuses({ type = "INVINCIBLE" }) then return end
		if #Proxy.adjacent(battle, caster, function(x) return Proxy.hostile(battle, caster, x) end) > 0 then return end
		local saved = Proxy.threat(battle, caster) * 0.5
		if saved < caster:getMaxHealth() then return end
		Proxy.credit(server, battle, caster, math.min(saved, caster:getAvailableHealth()) / caster:getMaxHealth() * Proxy.value(caster))
		Proxy.buff(server, battle, caster, { type = "BLOCKS_RETALIATION", val = 0, turns = 1 })
		return
	end

	if kind == "dash" then
		local t = self.turns or 3
		self:add(server, battle, caster, { type = "STACKS_SPEED", val = self.pct or 100, valueType = ENUM.BonusValueType.percentToAll,
			duration = ENUM.BonusDuration.nTurns, turns = t })
		self:add(server, battle, caster, { type = self.show, val = t, duration = ENUM.BonusDuration.nTurns, turns = t })
		logNumbers = { t }
	elseif kind == "forestRage" then
		local half = math.floor(caster:getDefense(false) / 2)
		self:add(server, battle, caster, { type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = -half })
		self:add(server, battle, caster, { type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = half })
		self:add(server, battle, caster, { type = "STACKS_SPEED", val = self.pct or 50, valueType = ENUM.BonusValueType.percentToAll })
		-- No more entangling: the chance of casting Entangle after attacks is pressed to 0
		self:add(server, battle, caster, { type = "SPELL_AFTER_ATTACK", subtype = "spell.bind", val = 0,
			valueType = ENUM.BonusValueType.independentMin, hidden = true })
		self:add(server, battle, caster, { type = self.show, val = half })
		logNumbers = { half }
	elseif kind == "flamestrike" then
		local dur = ENUM.BonusDuration.nTurns + ENUM.BonusDuration.untilAfterAttackSequence -- Bit marks added: removed within one round, or at the end of this round's exchange
		self:add(server, battle, caster, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeMelee", val = self.pct or 20, duration = dur, turns = 1 })
		self:add(server, battle, caster, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeRanged", val = self.pct or 20, duration = dur, turns = 1 })
		if self.spell then
			self:add(server, battle, caster, { type = "SPELL_AFTER_ATTACK", subtype = "spell." .. self.spell, val = 100, addInfo = { 0, 0 },
				duration = dur, turns = 1, hidden = true })
		end
		self:add(server, battle, caster, { type = self.show, val = self.pct or 20, duration = dur, turns = 1 })
		logNumbers = { self.pct or 20 }
	elseif kind == "powerFeed" then
		local sp = math.max(1, L.sp(caster))
		self:add(server, battle, caster, { type = "PRIMARY_SKILL", subtype = "primarySkill.spellpower", val = sp, propagator = "HERO", hidden = true })
		self:add(server, battle, caster, { type = self.show, val = sp })
		logNumbers = { sp }
	elseif kind == "invisible" then
		local t = self.turns or 3
		local key = mechanics:getSpell():getJsonKey()
		-- Bit marks added: removed after turns rounds, or at the end of its own exchange (invisible attacks get no retaliation, revealed after attacking)
		local dur = ENUM.BonusDuration.nTurns + ENUM.BonusDuration.untilAfterAttackSequence
		local function inv(desc)
			desc.sourceType, desc.sourceID = ENUM.BonusSource.spellEffect, key
			desc.sourceSecondaryID = mechanics:getEffectLevel() -- Round 339: since engine 89ce99f1, omitting the casting level means "any level", and looking at a stack's spell status reads the description with that level out of range, giving garbage; the level is stated
			desc.duration, desc.turns = desc.duration or dur, t
			self:add(server, battle, caster, desc)
		end
		inv({ type = "INVINCIBLE", val = 0, hidden = true })
		inv({ type = "BLOCKS_RETALIATION", val = 0, hidden = true })
		inv({ type = self.show, val = t })
		if self.revealScript then
			inv({ type = "COMBAT_EVENT_TRIGGER", subtype = self.revealScript, val = 0, hidden = true,
				duration = ENUM.BonusDuration.nTurns, stacking = "h5AbReveal", addInfo = { spell = key, mark = self.revealMark } })
		end
		logNumbers = { t }
	end

	if server:describeChanges() then
		-- The visual is the spell's own H5 effect (vfx_anim.json) or the creature's own cast animation; the borrowed H3 animation is no longer added (audit B III-1)
		if self.animation then server:showBattleAnimation(battle, { { unit = caster } }, self.animation, self.sound or "", 1.0, true) end
		server:refreshBattleUnits(battle)
		if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster) }, logNumbers) end
	end
	L.useCast(server, battle, caster, "h5AbSelfBuff" .. (kind or ""), self.uses)
end

return Script
