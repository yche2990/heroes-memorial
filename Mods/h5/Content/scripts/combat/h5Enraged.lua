local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Enraged
---
--- Attack rises when an own stack is wiped out (research_formulas.md, footnote of the Swordsman page on the Russian fandom wiki):
---   each dead stack counts separately as floor(base Attack of the dead creature x that stack's strength / total army strength), at least 1, added up per stack, for the whole battle.
---   Base Attack = the dead creature's own Attack (Attack from creature abilities, not from hero, artifacts or spells).
---   Strength = creature AI value x count at battle start; total army strength = sum over all counted stacks of its side. Summoned creatures, clones, war machines and arrow towers do not count (neither in the total nor when they die).
---   Stacks brought back to life count as alive again.
--- Recalculated at battle start, the start of each round, before its own strike, before being attacked and after acting (Attack only matters when striking and retaliating).
--- The bonus itself is a hidden Attack bonus, with a separate display bonus H5_ENRAGED_SHOW_H5C (value = current bonus).

local STACK = "h5Enraged"

local function counts(u)
	if u:isTurret() or u:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	if u:isClone() then return false end
	local ok, summoned = pcall(function() return u:copy():isSummoned() end)
	if ok and summoned then return false end
	return true
end

function Script:refresh(server, battle, unit)
	if not unit:isAlive() then return end
	local side = unit:getSide()
	local units = battle:getUnitsIf(function(u) return u:getSide() == side end)
	local total, deadList = 0, {}
	for _, u in ipairs(units) do
		if counts(u) then
			local p = math.max(1, u:getCreature():getAIValue()) * math.max(1, u:getBaseAmount())
			total = total + p
			if not u:isAlive() then table.insert(deadList, { u = u, p = p }) end
		end
	end
	local cur = H5.markValue(unit, STACK) or 0
	local want = 0
	if total > 0 then
		for _, d in ipairs(deadList) do
			-- Base Attack of the dead creature: the creature's own Attack (creatureAbility source)
			local atk = d.u:getBonusesValue({ type = "PRIMARY_SKILL", subtype = "primarySkill.attack", sourceType = ENUM.BonusSource.creatureAbility })
			want = want + math.max(1, math.floor(math.max(0, atk) * d.p / total))
		end
	end
	if cur == want then return end
	H5.removeByStacking(server, battle, unit, "PRIMARY_SKILL", STACK)
	H5.removeByStacking(server, battle, unit, "H5_ENRAGED_SHOW_H5C", STACK)
	if want > 0 then
		local src = unit:getCreature():getJsonKey()
		server:addUnitBonus(battle, unit, {
			type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = want,
			duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src,
			stacking = STACK, hidden = true
		}, false)
		server:addUnitBonus(battle, unit, {
			type = "H5_ENRAGED_SHOW_H5C", val = want,
			duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src,
			stacking = STACK
		}, false)
		if want > cur then
			server:refreshBattleUnits(battle)
			H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.8", { H5.name(unit) }, { want })
		end
	end
	H5.setMark(server, battle, unit, STACK, want, nil)
end

function Script:onBattleStart(server, battle, unit, other) self:refresh(server, battle, unit) end
function Script:onRoundStart(server, battle, unit, other) self:refresh(server, battle, unit) end
function Script:onBeforeAttack(server, battle, unit, other, payload) self:refresh(server, battle, unit) end
function Script:onBeforeAttacked(server, battle, unit, other, payload) self:refresh(server, battle, unit) end
function Script:onActionFinished(server, battle, unit, other, payload) self:refresh(server, battle, unit) end

return Script
