--- H6 Dynasty Weapons: common effect of active abilities (damage, healing, bonuses, damage over time, battlefield rules), once per battle / cooldown.
---
--- Targets (scope):
---   "target"    chosen by the spell's range and smart (click a stack or an area)
---   "adjacent"  the stack clicked plus stacks of the same side adjacent to it (Sky Father, Void Bane)
---   "all"       all stacks on the field matching side, no target needed (Sacrifice, Wheel of Fate...)
---   "strongest" the strongest enemy stack (AI value x count), no target needed (Lightning Lash)
---   "none"      touches no stacks, only adds battlefield bonuses (Law of the Wolf, Winds of Magic)
--- side: selectable stacks "ally" / "enemy" / "any" (relative to the caster); living: living only; walkers: non-flying only
---
--- On enemy stacks:
---   damage        "power" (spell effect value: hero Spell Power x spell power + level power, then adjusted by the target's resistance) or a fixed number
---   damagePercent percent of total health at battle start; dealtPercent/dealtMax: percent of the damage the target has dealt since battle start (H6DYN_DEALT), capped
---   enemies       { name = bonus } (json form, duration as turns or duration)
---   dot           { value = "power" or number, turns, spread, spreadTurns, anim }: attaches the damage-over-time script h6dynDot, dealing damage at the start of each round
--- On own stacks:
---   heal "power" or number; healPercent percent of total health at battle start; healLevel "heal"/"resurrect"
---   allies { name = bonus }
--- drainPercent: total damage dealt this time x percent restores health to every wounded living own stack (life drain, can resurrect fallen creatures of the stack)
--- battle: { name = bonus } added to the battlefield (affects both sides, e.g. BATTLE_CAN_FLEE); with sideParam = true in the bonus, the casting side is written into addInfo.side;
---         with everyUnit = true it is attached to every living stack at that time instead (the battlefield's own bonuses do not count down by rounds, so timed ones must be written this way)
--- damageAll: damage hits own stacks too (Firestorm)
--- control: control effects, not applied to enemy mind-immune stacks, commanders, war machines and capital guardians (own stacks as usual)
--- Damage: fixed numbers and percentages are also settled as spell damage (school reduction, protection spells, vulnerability, the hero's spell bonus), as "power" already is;
---       before landing it goes through Heavenly Armor / Frost Armor (Lib.damage)
--- animAlly / animEnemy: hit effects; sound unused (the spell's own cast sound)
--- onceIndex (unique in the whole mod), cooldown: once per battle / cooldown
local Base = require("spells/unitEffect")
local Lib = require("spells/h6dynLib")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function own(mechanics, unit)
	return unit:getSide() == mechanics:getCasterSide()
end

function Script:sideOk(mechanics, unit)
	local s = self.side or "any"
	if s == "ally" and not own(mechanics, unit) then return false end
	if s == "enemy" and own(mechanics, unit) then return false end
	return true
end

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) then return false end
	if unit:isTurret() then return false end
	if self.living and not unit:isLiving() then return false end
	if self.walkers and unit:hasBonuses({ type = "FLYING" }) then return false end
	if self.control and not own(mechanics, unit) and Lib.controlImmune(unit) then return false end
	return self:sideOk(mechanics, unit)
end

function Script:candidates(mechanics, noInvincible)
	return mechanics:getBattle():getUnitsIf(function(u)
		if noInvincible and u:isInvincible() then return false end
		return self:isValidTarget(mechanics, u) and self:isReceptive(mechanics, u)
	end)
end

function Script:applicableGeneral(mechanics, problem)
	if self.onceIndex and Lib.used(mechanics, self.onceIndex) then
		problem:addGeneric(mechanics)
		return false
	end
	local scope = self.scope or "target"
	if scope == "none" then return true end
	if scope == "target" or scope == "adjacent" then
		return Base.applicableGeneral(self, mechanics, problem)
	end
	if #self:candidates(mechanics) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local scope = self.scope or "target"
	if scope == "target" or scope == "adjacent" then
		return Base.applicableTarget(self, mechanics, problem, target)
	end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local scope = self.scope or "target"
	local battle = mechanics:getBattle()
	if scope == "none" then return {} end
	if scope == "all" then
		local out = {}
		for _, u in ipairs(self:candidates(mechanics)) do table.insert(out, { unit = u, hex = u:getPosition() }) end
		return out
	end
	if scope == "strongest" then
		local u = Lib.strongest(self:candidates(mechanics, true))
		if u then return { { unit = u, hex = u:getPosition() } } end
		return {}
	end
	local base = Base.transformTarget(self, mechanics, aimPoint, spellTarget)
	if scope ~= "adjacent" or #base == 0 then return base end
	local first = base[1].unit
	local seen = { [first:unitID()] = true }
	local out = { base[1] }
	local around = first:getSurroundingHexes()
	for i = 1, around:size() do
		local o = battle:getUnitByPos(around:at(i), true)
		if o and not seen[o:unitID()] and o:getSide() == first:getSide() and self:isValidTarget(mechanics, o) and self:isReceptive(mechanics, o) then
			seen[o:unitID()] = true
			table.insert(out, { unit = o, hex = o:getPosition() })
		end
	end
	return out
end

function Script:amount(mechanics, unit, spec)
	if spec == nil then return 0 end
	if spec == "power" then return mechanics:adjustEffectValue(unit) end
	return spec
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local spell = mechanics:getSpell()
	local key = spell:getJsonKey()
	local scope = self.scope or "target"
	local describe = server:describeChanges()
	if (scope == "target" or scope == "adjacent" or scope == "strongest") and #target == 0 then return end
	-- During the AI simulation (describeChanges false) no marks, no battlefield bonuses, no animations (checklist: addBattleBonus and showBattleAnimation in spell effect scripts are wrapped in describeChanges)
	if describe and self.onceIndex then Lib.markUsed(mechanics, server, self.onceIndex, self.cooldown) end

	-- Display bonuses added at runtime get a description and icon (spell name + the spell's status icon), otherwise they show blank
	local shown = { description = "@" .. spell:getNameTextID(), icon = "h6dyn/spells/" .. key .. "/Effect" }
	local totalDamage, totalKilled, firstHit, hits = 0, 0, nil, 0
	local animated = false
	local beamMain = nil   -- Round 316t: end point of the first jump of the lightning beam
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			local mine = own(mechanics, u)
			if ((not mine) or self.damageAll) and not u:isInvincible() then
				local amount = 0
				if self.damage == "power" then
					amount = mechanics:adjustEffectValue(u)
				else
					local raw = self.damage or 0
					if self.damagePercent then raw = raw + math.floor(Lib.initialHealth(u) * self.damagePercent / 100) end
					if self.dealtPercent then
						local d = math.floor(u:getBonusesValue({ type = "H6DYN_DEALT" }) * self.dealtPercent / 100)
						if self.dealtMax and d > self.dealtMax then d = self.dealtMax end
						raw = raw + d
					end
					amount = Lib.spellDamage(mechanics, spell, u, raw)
				end
				-- Round 316t: lightning beam (section 5 of the h6-vfx handoff notes): first from the caster to the stack clicked, then from it to every enemy adjacent to it
				if self.beam and describe and not mine then
					local to = u:getPosition()
					if beamMain == nil then
						local caster = mechanics:getUnitCaster()
						Lib.beamPlay(server, battle, self.beam, caster and caster:getPosition() or Lib.beamHeroHex(to, mechanics:getCasterSide()), to)
						beamMain = to
					else
						Lib.beamPlay(server, battle, self.beam, beamMain, to)
					end
					animated = true
				end
				if not mine and self.animEnemy then animated = (describe and Lib.anim(server, battle, u, self.animEnemy)) or animated end
				if mine and self.animAlly then animated = (describe and Lib.anim(server, battle, u, self.animAlly)) or animated end
				if amount > 0 then
					local dmg, killed = Lib.damage(server, battle, u, amount)
					totalDamage = totalDamage + (dmg or 0)
					totalKilled = totalKilled + (killed or 0)
					hits = hits + 1
					firstHit = firstHit or u
				end
			elseif mine and self.animAlly then
				animated = (describe and Lib.anim(server, battle, u, self.animAlly)) or animated
			end
			if u:isAlive() then
				if mine then
					local heal = self:amount(mechanics, u, self.heal)
					if self.heal == "power" then heal = mechanics:getEffectValue() end
					if self.healPercent then heal = heal + math.floor(Lib.initialHealth(u) * self.healPercent / 100) end
					if heal > 0 and u:getAvailableHealth() < u:getTotalHealth() then
						local level = (self.healLevel == "resurrect") and ENUM.HealLevel.resurrect or ENUM.HealLevel.heal
						if Lib.ringOfOblivion(u) then level = ENUM.HealLevel.heal end
						server:healUnit(battle, u, heal, level, ENUM.HealPower.permanent)
					end
					for _, b in pairs(self.allies or {}) do Lib.addBonus(server, battle, u, b, "SPELL_EFFECT", key, false, shown) end
					if describe then Lib.statuses(server, battle, u, self.statusAllies, mechanics:getUnitCaster()) end
				else
					for _, b in pairs(self.enemies or {}) do Lib.addBonus(server, battle, u, b, "SPELL_EFFECT", key, false, shown) end
					if describe then Lib.statuses(server, battle, u, self.statusEnemies, mechanics:getUnitCaster()) end
					if self.dot then
						-- Review B7 (2026-11-08): raw = damage per round not adjusted for the target, per = adjusted for this target (school reduction, protection, immunity, the hero's spell damage bonus).
						-- "power" is adjusted by adjustEffectValue; fixed values (Deadly Toxin 100, Shadow Poison 5 per creature) used to be unadjusted and are now converted as spell damage.
						-- raw is written into addInfo and converted again for the new target when spreading to other stacks (combat/h6dynDot)
						local raw, per
						if self.dot.value == "power" then
							raw = mechanics:getEffectValue()
							per = self:amount(mechanics, u, self.dot.value)
						else
							raw = self.dot.value or 0
							if self.dot.perCreature and mechanics:getUnitCaster() then
								raw = raw + self.dot.perCreature * mechanics:getUnitCaster():getCount()
							end
							per = Lib.spellDamage(mechanics, spell, u, raw)
						end
						if per > 0 then
							Lib.addBonus(server, battle, u, {
								type = "COMBAT_EVENT_TRIGGER", subtype = Lib.MOD .. ":h6dynDot", val = per,
								turns = self.dot.turns or 3, stacking = "h6dynDot_" .. key,
								addInfo = { spread = self.dot.spread or 0, spreadTurns = self.dot.spreadTurns or 0,
								            anim = self.dot.anim or "", spell = key, tag = "h6dynDot_" .. key, bonuses = self.dot.bonuses,
								            status = self.dot.status, raw = raw }
							}, "SPELL_EFFECT", key, false, shown)
						end
					end
				end
			end
		end
	end

	if self.drainPercent and totalDamage > 0 then
		local heal = math.floor(totalDamage * self.drainPercent / 100)
		for _, a in ipairs(battle:getUnitsIf(function(x) return x:getSide() == mechanics:getCasterSide() and x:isAlive() and not x:isTurret() end)) do
			if a:getAvailableHealth() < a:getTotalHealth() then
				if self.animAlly then animated = (describe and Lib.anim(server, battle, a, self.animAlly)) or animated end
				server:healUnit(battle, a, heal, Lib.ringOfOblivion(a) and ENUM.HealLevel.heal or ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
			end
		end
	end

	for _, b in pairs(describe and self.battle or {}) do
		local d = {}
		for k, v in pairs(b) do if k ~= "sideParam" and k ~= "everyUnit" then d[k] = v end end
		if b.sideParam then
			local info = {}
			for k, v in pairs(d.addInfo or {}) do info[k] = v end
			info.side = mechanics:getCasterSide()
			d.addInfo = info
		end
		if d.turns and d.turns > 0 and not d.duration then d.duration = "N_TURNS" end
		d.duration = d.duration or "ONE_BATTLE"
		d.sourceType = d.sourceType or "SPELL_EFFECT"
		d.sourceID = d.sourceID or key
		-- Review A1 (2026-11-08): when a spell effect source has no casting level the engine records it as "any level" (5), and right-clicking the stack reads the description array out of range; 0 is filled in as in Lib.addBonus
		if d.sourceType == "SPELL_EFFECT" and d.sourceSecondaryID == nil then d.sourceSecondaryID = 0 end
		if b.everyUnit then
			-- The battlefield's own bonuses do not count down by rounds, so timed ones are attached to every living stack
			for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() end)) do
				server:addUnitBonus(battle, u, d, false)
			end
		else
			server:addBattleBonus(battle, d)
		end
	end

	if describe and hits > 0 then
		BattleLog.spellDamage(server, battle, spell, hits == 1 and firstHit or nil, totalDamage, totalKilled)
	end
	if animated then server:refreshBattleUnits(battle) end
end

return Script
