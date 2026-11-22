local Base = require("combat/combatScript")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Goblin: Treachery
---
--- When its count drops below val% of the starting count (original 30%) it defects to the enemy, once per battle, until the battle ends.
--- How: applies the effect of Puppet Master (hypnotize, Expert) until the battle ends; the original "stays with the new master after battle" cannot be done (the engine cannot change armies during battle).
--- Blood Rage level 2 cancels Treachery (H5_NO_TREACHERY_H5C). Summoned creatures and clones do not defect.
---
--- Parameter: val

local DONE = "H5_TREACHERY_DONE_H5C"

function Script:check(server, battle, unit)
	if unit == nil or not unit:isAlive() or unit:isClone() or L.isSummoned(unit) then return end
	if unit:hasBonuses({ type = DONE }) or unit:hasBonuses({ type = "H5_NO_TREACHERY_H5C" }) then return end
	if unit:hasBonuses({ type = "HYPNOTIZED" }) then return end
	local base = unit:getBaseAmount()
	if base <= 0 or unit:getCount() * 100 >= base * (self.val or 30) then return end

	local spell = LIBRARY:getSpellByName("hypnotize")
	if spell == nil then return end
	server:addUnitBonus(battle, unit, {
		type = DONE, val = 1, duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), hidden = true
	}, false)
	server:applySpellEffects(battle, unit, spell, { unit }, 3, 1000, true)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append = { "core.bonus." .. DONE .. ".description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }
	})
end

function Script:onAfterAttacked(server, battle, unit, other, payload) self:check(server, battle, unit) end
function Script:onActionFinished(server, battle, unit, other, payload) self:check(server, battle, unit) end
function Script:onRoundStart(server, battle, unit, other, payload) self:check(server, battle, unit) end
function Script:onBattleStart(server, battle, unit, other, payload) self:check(server, battle, unit) end

return Script
