local Base = require("combat/combatScript")
local H5R = require("combat/h5Common")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Magnetic Golem: Enchanted Obsidian
---
--- Damage magic does not hurt it but restores val% of the damage instead (original EnchantedObsidian_DamageToHealCoef = 0.5), can resurrect;
--- physical "magic" such as Fist of Wrath and Call Lightning still deals damage.
--- Not affected by other magic: when non-damage magic cast by a hero or stack lands on it, all effects of that spell are removed at once (same as immunity).
--- Limitation: the engine only raises this event for "active casts"; spells cast with attacks, spell-like attacks and script casts do not come through here.

local PHYSICAL = { "magicfist", "calllightning" }

local function isPhysical(spell)
	local k = string.lower(spell:getJsonKey())
	for _, p in ipairs(PHYSICAL) do
		if string.find(k, p, 1, true) then return true end
	end
	return false
end

local function sameSpell(sourceId, spell)
	if sourceId == nil then return false end
	local k = spell:getJsonKey()
	if sourceId == k then return true end
	local short = string.match(k, ":(.+)$") or k
	local s2 = string.match(tostring(sourceId), ":(.+)$") or tostring(sourceId)
	return s2 == short
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local spell = payload.spell
	if spell == nil or unit:isGhost() then return end
	local entry = self:ownEntry(unit, payload)

	if spell:isDamage() then
		if isPhysical(spell) then return end
		if entry == nil or entry.unitBefore == nil then return end
		local lost = math.max(0, entry.unitBefore:getAvailableHealth() - unit:getAvailableHealth())
		if lost <= 0 then return end
		local heal = lost + math.floor(lost * (self.val or 50) / 100)
		local amt, lvl = H5R.reviveHeal(unit, heal)
		local healed = amt > 0 and server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.permanent) or 0
		server:refreshBattleUnits(battle)
		server:appendLog(battle, {
			append = { "core.bonus.H5_OBSIDIAN_H5C.description.1" },
			replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
			replaceNumbers = { math.max(0, (healed or heal) - lost) }
		})
		return
	end

	if not unit:isAlive() then return end
	local mine = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		return sameSpell(b:getSourceID(), spell)
	end)
	if mine:size() > 0 then
		server:removeUnitBonuses(battle, unit, mine)
		server:refreshBattleUnits(battle)
	end
end

return Script
