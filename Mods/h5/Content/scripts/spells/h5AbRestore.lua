local Base = require("spells/unitEffect")
local H5R = require("combat/h5Common")
local L = require("spells/h5AbLib")
local C = L.C
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Healing and resurrection active abilities of H5 creatures (on a friendly stack or a corpse):
---   mode = "layHands"   Lay Hands (Paladin): the top wounded creature of the target is fully healed (no resurrection); dispelling negative magic is a separate effect in the spell. Once per battle
---   mode = "repair"     Repair (Master Gremlin): a mechanical creature or war machine regains per x gremlin count health, can resurrect (permanently). Unlimited
---   mode = "resurrect"  Resurrect Allies (Archangel): a friendly stack (alive or dead, corpse not covered) regains per x archangel count health, can resurrect (permanently);
---                       cannot resurrect Archangels themselves. Once per battle
---   mode = "union"      Symbiosis (Dryad): a friendly treant stack regains per x dryad count health (can resurrect, permanently), and the dryads regain selfPer x dryad count. Once per battle
---   mode = "scavenger"  Scavenger (Lightning Wyvern): eats a corpse within movement range (not summoned or a clone), regaining corpse total health x pct% (can resurrect, permanently); the corpse disappears. Unlimited
---   mode = "swallow"    Eat Goblin (Cyclops): eats an adjacent friendly goblin, the top creature is fully healed. Unlimited
---   mode = "sacrifice"  Sacrifice Goblin (Earth Daughter, Sky Daughter): sacrifices an adjacent friendly goblin, +1 own Attack, Defense and Morale (at most +max),
---                       casts +casts (original: restores 2 x goblin health mana). Unlimited
--- Parameters: mode, per, selfPer, pct, max, casts, uses, mark (bonus name for the battle log), show (display bonus type of the sacrifice)

local function injuries(u)
	return u:getMaxHealth() - u:getFirstHPleft()
end

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return false end
	local mode = self.mode
	local side = caster:getSide()
	if unit:isGhost() or unit:isClone() or unit:isTurret() then return false end

	if mode == "scavenger" then
		if not unit:isDead() then return false end
		local ok, summoned = pcall(function() return unit:copy():isSummoned() end)
		if ok and summoned then return false end
		local ok2, speed = pcall(function() return caster:getBonusesValue({ type = "STACKS_SPEED" }) end)
		if ok2 and speed and speed > 0 and C.unitDistance(caster, unit) > speed + 1 then return false end
		return true
	end

	if mechanics:getBattle():isHostile(caster, unit) then return false end

	if mode == "resurrect" then
		-- The same creature cannot be resurrected (shrunk and downgraded copies compared by source creature)
		if C.sourceKey(unit) == C.sourceKey(caster) then return false end
		if unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
		if unit:isDead() then
			local hexes = unit:getHexes()
			for i = 1, hexes:size() do
				local blockers = mechanics:getBattle():getUnitsIf(function(o) return o:isValidTarget(false) and o:coversPos(hexes:at(i)) end)
				if #blockers > 0 then return false end
			end
			return true
		end
		return unit:isAlive() and unit:getAvailableHealth() < unit:getTotalHealth()
	end

	if not unit:isAlive() then return false end
	if mode == "layHands" then return injuries(unit) > 0 or unit:getAvailableHealth() < unit:getTotalHealth() end
	if mode == "repair" then
		if not (C.isMechanical(unit) or unit:hasBonuses({ type = "SIEGE_WEAPON" })) then return false end
		return unit:getAvailableHealth() < unit:getTotalHealth()
	end
	if mode == "union" then return L.isTreant(unit) end
	if mode == "swallow" or mode == "sacrifice" then
		return unit:unitID() ~= caster:unitID() and L.isGoblin(unit) and L.adjacent(caster, unit)
	end
	return false
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	return false
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	if self.mode == "swallow" and injuries(caster) <= 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	local found = mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end)
	if #found == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

--- Corpses and wounded targets do not go through the engine's "accepts spell" filter
function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

local function consumeOne(server, battle, unit)
	if unit:getCount() <= 1 then server:removeUnit(battle, unit) else server:damageUnit(battle, unit, unit:getFirstHPleft()) end
end

function Script:heal(server, battle, unit, amount, resurrect)
	if amount <= 0 then return 0, 0 end
	local lvl = ENUM.HealLevel.heal
	if resurrect then amount, lvl = H5R.reviveHeal(unit, amount) end
	if amount <= 0 then return 0, 0 end
	return server:healUnit(battle, unit, amount, lvl, ENUM.HealPower.permanent)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	local unit = dest and dest.unit
	if unit == nil then return end
	local mode = self.mode
	local n = caster:getCount()
	local healed, raised = 0, 0
	local animUnit = unit

	-- Round 344: AI simulation branch (ai-skills-design #37 Sacrifice Goblin, #38 Eat Goblin). Using up a friendly goblin is vetoed by the AI as an own loss:
	-- in the simulation nothing is eaten or sacrificed. Eat: the Cyclops is healed by "topping up the top creature - one goblin's value converted to Cyclops health"; not used if the net is below one goblin's health.
	-- Sacrifice: gain (+1 Attack, Defense and Morale each, only casts once max layers are reached; estimated as stack value x (2.5% + 2% + 2%) and 0.045 x level 2 x casts / 8)
	-- - one goblin's value, the net booked, then capped as a weak ability. Real casts do not go through here
	if (mode == "swallow" or mode == "sacrifice") and Proxy.trial(server) then
		if mode == "swallow" then
			local net = injuries(caster) - Proxy.costHp(unit, 1, caster)
			if net >= unit:getMaxHealth() then server:healUnit(battle, caster, math.floor(net), ENUM.HealLevel.heal, ENUM.HealPower.permanent) end
		else
			local stack = Proxy.value(caster) * caster:getCount()
			local gain = stack * 0.045 * 2 * (self.casts or 1) / 8
			if L.usedCount(caster, "h5AbSacrificeStacks") < (self.max or 5) then gain = gain + stack * 0.065 end
			local net = gain - Proxy.value(unit)
			local e = Proxy.nearestHostile(battle, caster)
			if net > 0 and e ~= nil then
				Proxy.damage(server, battle, e, Proxy.capWeak(Proxy.hpOf(net, e), battle, caster, e))
			end
		end
		return
	end

	if mode == "layHands" then
		healed, raised = self:heal(server, battle, unit, injuries(unit), false)
	elseif mode == "repair" or mode == "resurrect" then
		healed, raised = self:heal(server, battle, unit, (self.per or 5) * n, true)
	elseif mode == "union" then
		healed, raised = self:heal(server, battle, unit, (self.per or 20) * n, true)
		self:heal(server, battle, caster, (self.selfPer or 4) * n, true)
	elseif mode == "scavenger" then
		local amount = math.floor(unit:getTotalHealth() * (self.pct or 20) / 100)
		server:removeUnit(battle, unit)
		healed, raised = self:heal(server, battle, caster, amount, true)
		animUnit = caster
	elseif mode == "swallow" then
		consumeOne(server, battle, unit)
		healed, raised = self:heal(server, battle, caster, injuries(caster), false)
		animUnit = caster
	elseif mode == "sacrifice" then
		consumeOne(server, battle, unit)
		local stacks = L.usedCount(caster, "h5AbSacrificeStacks")
		if stacks < (self.max or 5) then
			C.setMark(server, battle, caster, "h5AbSacrificeStacks", stacks + 1)
			local function add(desc) desc.duration = ENUM.BonusDuration.oneBattle; L.addBonus(server, battle, caster, desc, true) end
			add({ type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = 1 })
			add({ type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = 1 })
			add({ type = "MORALE", val = 1 })
			if self.show then
				C.removeByStacking(server, battle, caster, self.show, "h5AbSacrificeShow")
				add({ type = self.show, val = stacks + 1, stacking = "h5AbSacrificeShow" })
			end
		end
		if (self.casts or 1) > 0 then
			local add2 = { type = "CASTS", val = self.casts or 1, hidden = true, duration = ENUM.BonusDuration.oneBattle }
			L.addBonus(server, battle, caster, add2, true)
		end
		animUnit = caster
		healed = stacks + 1
	end

	if server:describeChanges() then
		-- The visual is the spell's own H5 effect; the borrowed H3 animation is no longer added (audit B III-1)
		if self.animation then server:showBattleAnimation(battle, { { unit = animUnit } }, self.animation, self.sound or "", 0.6, true) end
		server:refreshBattleUnits(battle)
		if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster), C.name(animUnit) }, { healed, raised or 0 }) end
	end
	L.useCast(server, battle, caster, "h5AbRestore" .. (mode or ""), self.uses)
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): creature healing / resurrection abilities
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local BY_MODE = {
		layHands = { [1] = "combatHeal" },
		repair = { [1] = "combatHeal" },
		resurrect = { [1] = "combatHeal" },
		sacrifice = { [1] = "combatSacrifice" },
		scavenger = { [1] = "combatSacrifice" },
		swallow = { [1] = "combatSacrifice" },
		union = { [1] = "combatHeal" },
	}
	local CURSORS = BY_MODE[self.mode or ""] or { [1] = "combatHeal" }
	local AIM = { ["*"] = "creature" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Hover estimate: same formula as apply, computed with self:heal on a copy (with the Ring of Oblivion on the field only the top creature is healed, no resurrection).
--- Holy Heal, Repair, Resurrect Ally and Symbiosis show the target's restored health and resurrected count (the dryad's own share in Symbiosis is not counted);
--- Scavenger and Devouring Goblin show what the caster itself heals; Sacrifice Goblin does not change health and returns 0
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		if caster == nil or not caster:isAlive() then return zero end
		local dest = self:filterTarget(mechanics, spellTarget or {})[1]
		local unit = dest and dest.unit
		if unit == nil then return zero end
		local mode = self.mode
		local n = caster:getCount()
		local who, amount, resurrect = unit, 0, false
		if mode == "layHands" then
			amount = injuries(unit)
		elseif mode == "repair" or mode == "resurrect" then
			amount, resurrect = (self.per or 5) * n, true
		elseif mode == "union" then
			amount, resurrect = (self.per or 20) * n, true
		elseif mode == "scavenger" then
			who, amount, resurrect = caster, math.floor(unit:getTotalHealth() * (self.pct or 20) / 100), true
		elseif mode == "swallow" then
			who, amount = caster, injuries(caster)
		else
			return zero
		end
		local lvl = ENUM.HealLevel.heal
		if resurrect then amount, lvl = H5R.reviveHeal(who, amount) end
		amount = math.floor(amount)
		if amount <= 0 then return zero end
		local healed, raised = who:copy():heal(amount, lvl, ENUM.HealPower.permanent)
		return { hpDelta = healed or 0, unitsDelta = raised or 0, unitType = who:getCreature() }
	end)
	if ok and result then return result end
	return zero
end

return Script
