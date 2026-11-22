local Base = require("spells/spellEffect")
local C = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Mana of H5 spellcasting creatures (a shared mana pool, deducted by spell cost). Attached to every H5 creature spell (h5Ab*) a caster uses.
--- The stack's mana = value of the hidden bonus H5_MANA_H5C (the creature's own SpellPoints + what creature experience adds), full at the start of each battle;
--- mana used is recorded on the hidden mark h5ManaUsed.
---   applicableGeneral: cannot be cast when the caster's remaining mana is below this spell's cost (parameter mana) (the engine's casts are unaffected; blocked separately here).
---   apply: mana is deducted on a real cast; if afterwards the remaining mana is not enough even for the cheapest spell (H5_MANA_MIN_H5C) and the stack has no active ability without mana cost,
---          a negative casts bonus presses the remaining casts to 0 so it stops (the interface no longer shows it as able to cast).
--- Casters without the mana bonus (heroes, other creatures, ability-triggered casts) are unaffected.
--- Parameter: mana

local USED = "h5ManaUsed"
local DONE = "h5ManaCasts"

function Script.manaOf(unit)
	if unit == nil then return nil end
	local ok, has = pcall(function() return unit:hasBonuses({ type = "H5_MANA_H5C" }) end)
	if not ok or not has then return nil end
	local total = unit:getBonusesValue({ type = "H5_MANA_H5C" })
	return total - (C.markValue(unit, USED) or 0), total
end

function Script:applicableGeneral(mechanics, problem)
	local left = Script.manaOf(mechanics:getUnitCaster())
	if left ~= nil and left < (self.mana or 0) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	return true
end

function Script:apply(mechanics, server, target)
	if not server:describeChanges() then return end
	local caster = mechanics:getUnitCaster()
	local left = Script.manaOf(caster)
	if left == nil then return end
	local battle = mechanics:getBattle()
	local used = (C.markValue(caster, USED) or 0) + (self.mana or 0)
	C.setMark(server, battle, caster, USED, used, nil)
	local done = (C.markValue(caster, DONE) or 0) + 1
	C.setMark(server, battle, caster, DONE, done, nil)
	left = left - (self.mana or 0)
	local cheapest = caster:getBonusesValue({ type = "H5_MANA_MIN_H5C" })
	local keep = caster:hasBonuses({ type = "H5_MANA_KEEPCASTS_H5C" })
	if left < cheapest and not keep then
		local stop = caster:getBonuses({ type = "CASTS" }):filter(function(b) return b:getStacking() == "h5ManaOut" end)
		-- The engine deducts this cast after the effect (spendMana), so the total is pressed to "casts used (including this one)", leaving exactly 0 without ammo overuse
		local total = caster:getBonusesValue({ type = "CASTS" })
		if stop:size() == 0 and total > done then
			server:addUnitBonus(battle, caster, {
				type = "CASTS", val = done - total, duration = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(),
				stacking = "h5ManaOut", hidden = true
			}, false)
		end
	end
end

return Script
