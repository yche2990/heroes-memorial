local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Wasp Swarm (H7): the swarm clings to an enemy stack (added by the spell spells/h7WaspSwarm).
--- When it stings: takes dmg physical damage (no magic resistance; not more than the stack's current health), Luck -2 (H7's -30), until the end of its current action.
--- When the possessed stack's own action ends (wait and defend included; in H7 the swarm leaves at the start of its turn while the Luck penalty lasts until the end of the turn),
--- the Luck penalty is removed and the swarm moves to another stack of that side (preferring ones this swarm has not stung yet, chosen at random),
--- val = remaining moves (3/4/6/8 stacks affected in total = first target + val moves). The swarm disperses if the stack dies.
--- Parameters: dmg, spell, icon; val = remaining moves

Script.LUCK = "h7WaspLuck"
Script.TRIGGER = "h7WaspSwarm"
Script.HIT = "h7WaspHit"

--- Sting a stack and leave the swarm on it (remaining = moves left afterwards)
function Script.sting(server, battle, unit, dmg, remaining, spellKey, icon, eventScript, level)
	if not unit:isAlive() then return end
	local describe = server:describeChanges()
	if describe then
		server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7eWaspSwarm", "h7/spell_wasp_swarm_impact.ogg", 1.0, true)
	end
	local amount = math.min(math.floor(dmg), unit:getAvailableHealth())
	if unit:isInvincible() then amount = 0 end
	if amount > 0 then
		local _, killed = server:damageUnit(battle, unit, amount)
		if describe then BattleLog.creaturesPerish(server, battle, unit, killed) end
	elseif describe then
		server:refreshBattleUnits(battle)
	end
	if not unit:isAlive() then return end
	E.setMark(server, battle, unit, Script.HIT, 1, nil)
	E.removeBy(server, battle, unit, "LUCK", Script.LUCK)
	server:addUnitBonus(battle, unit, {
		type = "LUCK", val = -2, duration = "ONE_BATTLE",
		sourceType = "SPELL_EFFECT", sourceID = spellKey, sourceSecondaryID = level or 0, stacking = Script.LUCK
	}, true)
	-- H7 audit B6: if this stack already carries a swarm (from another cast), the two merge into one, keeping the larger number of remaining moves instead of losing one
	local okOld, old = pcall(function()
		return unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == Script.TRIGGER end)
	end)
	if okOld and old then
		for i = 1, old:size() do
			local v = old:getBonus(i):getVal() or 0
			if v > remaining then remaining = v end
		end
	end
	E.removeBy(server, battle, unit, "COMBAT_EVENT_TRIGGER", Script.TRIGGER)
	local d = {
		type = "COMBAT_EVENT_TRIGGER",
		subtype = eventScript or "heroes-memorial.h7:h7WaspSwarmJump",
		val = math.max(0, remaining),
		duration = "ONE_BATTLE",
		sourceType = "SPELL_EFFECT",
		sourceID = spellKey,
		sourceSecondaryID = level or 0, -- H7 audit A1: the casting level is written (right-clicking a stack picks the description by level)
		stacking = Script.TRIGGER,
		addInfo = { dmg = math.floor(dmg), spell = spellKey, icon = icon or "", level = level or 0 }
	}
	if icon and icon ~= "" then d.icon = icon end
	server:addUnitBonus(battle, unit, d, true)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	E.removeBy(server, battle, unit, "LUCK", Script.LUCK)
	E.removeBy(server, battle, unit, "COMBAT_EVENT_TRIGGER", Script.TRIGGER)
	local left = self.val or 0
	if left <= 0 then
		if unit:isAlive() then
			server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7eWaspSwarmFade", "", 1.0, true)
			server:refreshBattleUnits(battle)
		end
		return
	end
	local side, myId = unit:getSide(), unit:unitID()
	local all = battle:getUnitsIf(function(u)
		return u:unitID() ~= myId and u:getSide() == side and E.real(u) and not u:isInvincible()
			and not E.spellImmune(u, self.spell, 4)
	end)
	if #all == 0 then return end
	local fresh = {}
	for _, u in ipairs(all) do
		if E.markVal(u, Script.HIT) == nil then fresh[#fresh + 1] = u end
	end
	local pool = (#fresh > 0) and fresh or all
	local nextUnit = pool[server:rngInt(1, #pool)]
	Script.sting(server, battle, nextUnit, self.dmg or 0, left - 1, self.spell, self.icon, nil, self.level)
end

return Script
