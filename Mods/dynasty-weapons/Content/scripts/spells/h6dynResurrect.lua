--- H6 Dynasty Weapon, Angel Alliance level 4 "Resurrection" (H6 Resurrection, Ability 5220425):
---   once per battle; can only be cast on a dead own stack (corpse); restores a fixed value of health and resurrects, permanently (kept after this battle).
---   With the Ring of Oblivion in play only healing, no resurrection (no living creature to heal, so no effect).
--- Level 5 "Improved Resurrection" (Ability 5220442): when the hero has the hidden bonus H6DYN_IMPROVED_RES (val = damage percent),
---   the resurrected stack deals +val% damage for improvedTurns rounds. The hero's bonus passes to its own stacks, so the value is read on the resurrected stack.
--- Parameters: value (healing), improvedTurns, onceIndex (once-per-battle id), bonusText (description of Improved Resurrection, registered as translatable text), plus healLevel/healPower of the core heal
local Base = require("spells/heal")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:getHealAmount(mechanics, unit, server)
	return self.value or 0
end

function Script:applicableGeneral(mechanics, problem)
	if Lib.used(mechanics, self.onceIndex or 1) then
		problem:addGeneric(mechanics)
		return false
	end
	-- battle:getUnitsIf only returns living stacks (the predicate is called for corpses but they are not in the result), so a side effect is used to find corpses
	local any = false
	mechanics:getBattle():getUnitsIf(function(unit)
		if not any and self:isValidTarget(mechanics, unit) and self:isReceptive(mechanics, unit) and mechanics:ownerMatches(unit) then any = true end
		return false
	end)
	if not any then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

--- The target is the corpse clicked (the core transformByRange also uses getUnitsIf and finds no corpses)
function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local result = {}
	for _, dest in ipairs(aimPoint) do
		local unit = dest.unit
		if not unit and dest.hex and dest.hex:isValid() then
			mechanics:getBattle():getUnitsIf(function(u)
				if not unit and u:coversPos(dest.hex) and self:isValidTarget(mechanics, u) then unit = u end
				return false
			end)
		end
		if unit and self:isValidTarget(mechanics, unit) and self:isReceptive(mechanics, unit) and mechanics:ownerMatches(unit) then
			table.insert(result, { unit = unit })
		end
	end
	return result
end

function Script:isValidTarget(mechanics, unit)
	if not unit:isDead() then return false end
	if unit:isClone() then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	if #target == 0 then return end -- The server does not check the clicked target (the client blocks it); without a valid target it does not count as used
	if server:describeChanges() then Lib.markUsed(mechanics, server, self.onceIndex or 1) end
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit then
			local level = self:getHealLevel()
			if Lib.ringOfOblivion(unit) then level = ENUM.HealLevel.heal end
			local healed, resurrected = server:healUnit(battle, unit, self:getHealAmount(mechanics, unit, server), level, self:getHealPower())
			if resurrected > 0 and server:describeChanges() then
				local pct = unit:getBonusesValue({ type = "H6DYN_IMPROVED_RES" })
				if pct > 0 then
					server:addUnitBonus(battle, unit, {
						type       = "GENERAL_DAMAGE_PREMY",
						val        = pct,
						duration   = ENUM.BonusDuration.nTurns,
						turns      = self.improvedTurns or 2,
						sourceType = ENUM.BonusSource.spellEffect,
						sourceID   = mechanics:getSpell():getJsonKey(),
						sourceSecondaryID = mechanics:getEffectLevel(), -- Round 339: since engine 89ce99f1, omitting the casting level means "any level", and looking at a stack's spell status reads the description with that level out of range, giving garbage (log: Unable to find localization); the level is stated
						stacking   = "h6dynImprovedResurrection",
						description = self.bonusText and ("@" .. self.bonusText) or nil,
						icon       = "h6dyn/spells/h6dynResurrection/Effect"
					}, false)
				end
				server:appendLog(battle, {
					append         = { resurrected == 1 and "core.genrltxt.117" or "core.genrltxt.116" },
					replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
					replaceNumbers = { resurrected }
				})
			end
		end
	end
end

return Script
