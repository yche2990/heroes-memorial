local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Weakening Strike (Plague Zombie)
--- Every hit on an enemy (attack and retaliation) gives the target -val Attack and Defense, cumulative for the whole battle, never below 0;
--- targets with Unbreakable Armor (H5_ARMORED_H5C) do not lose Defense. H5_WEAKENED_SHOW_H5C is attached for display (value = total Attack lost). Parameter: val

local STACK = "h5WeakeningStrike"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = H5.firstTarget(payload)
	if entry == nil or entry.unit == nil then return end
	local t = entry.unit
	if not t:isAlive() or t:isInvincible() or not battle:isHostile(unit, t) or (entry.damage or 0) <= 0 then return end
	if t:hasBonuses({ type = "SIEGE_WEAPON" }) then return end
	local v = self.val or 2
	local src = unit:getCreature():getJsonKey()
	local da = math.min(v, math.max(0, t:getAttack(false)))
	local dd = 0
	if not t:hasBonuses({ type = "H5_ARMORED_H5C" }) then dd = math.min(v, math.max(0, t:getDefense(false))) end
	if da <= 0 and dd <= 0 then return end
	-- Round 375: Attack/Defense loss is cumulative for the whole battle. Of bonuses with the same stacking group, type and subtype the engine keeps only the largest; it used to attach -v each time
	-- which in fact lowered it only once; now the old one is removed and one is reattached with the total (Attack total in mark STACK, Defense in STACK .. "Def")
	local totA = (H5.markValue(t, STACK) or 0) + da
	local totD = (H5.markValue(t, STACK .. "Def") or 0) + dd
	H5.removeByStacking(server, battle, t, "PRIMARY_SKILL", STACK)
	local function add(sub, val)
		if val <= 0 then return end
		server:addUnitBonus(battle, t, {
			type = "PRIMARY_SKILL", subtype = sub, val = -val,
			duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = STACK, hidden = true
		}, true)
	end
	add("primarySkill.attack", totA)
	add("primarySkill.defence", totD)
	local shown = totA
	H5.setMark(server, battle, t, STACK, shown, nil)
	H5.setMark(server, battle, t, STACK .. "Def", totD, nil)
	H5.removeByStacking(server, battle, t, "H5_WEAKENED_SHOW_H5C", STACK)
	server:addUnitBonus(battle, t, {
		type = "H5_WEAKENED_SHOW_H5C", val = shown,
		duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = STACK
	}, false)
	server:showBattleAnimation(battle, { { unit = t } }, "h5/fx/Spells_Weakness", "", 0.6, true)
	server:refreshBattleUnits(battle)
end

return Script
