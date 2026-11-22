local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Dwarven Shieldwall (Shieldguard)
--- When attacked from anywhere but the flank (ranged, or melee with the attacker not behind it), Defense +val (original +5, scaled to +9 by level 2 Attack/Defense);
--- such attacks and counterattacks cannot incapacitate it: after the hit (and when this action ends) the NOT_ACTIVE-type effects this attack brought are removed
--- (Stun, Paralyze, Petrify, Blind etc., together with attached effects of the same source such as no counterattack).
--- The engine has no facing for flanking; "behind" is judged by battle:isToReverse (same "behind" as the pack's Backstab h47Backstab).
--- The creature also carries the hidden mark H7_NO_INCAPACITATE_H7C (value 1), which batch B stun scripts can read directly to skip it.

local TMP = "h7ShieldwallTmp"
local NF = "h7ShieldwallNF"
local PRE = "h7SWPre|"   -- Yu's decision (H7 audit C1): only what this hit brought is removed. Existing NOT_ACTIVE effects are recorded before the hit (one mark each) and are not removed afterwards

local function sig(b)
	return PRE .. tostring(b:getSource()) .. ":" .. tostring(b:getSourceID()) .. ":" .. tostring(b:getStacking()) .. ":" .. tostring(b:getVal())
end

local function snapshot(server, battle, unit)
	local na = unit:getBonuses({ type = "NOT_ACTIVE" })
	for i = 1, na:size() do A.setMark(server, battle, unit, sig(na:getBonus(i)), 1, 1) end
end

local function clearSnapshot(server, battle, unit)
	local list = unit:getBonuses({ type = A.MARK }):filter(function(b)
		return string.sub(b:getStacking() or "", 1, #PRE) == PRE
	end)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

local function clearTmp(server, battle, unit)
	A.removeByStacking(server, battle, unit, "PRIMARY_SKILL", TMP)
end

local function stripIncap(server, battle, unit)
	if not unit:isAlive() then return end
	local na = unit:getBonuses({ type = "NOT_ACTIVE" }):filter(function(b)
		return A.markValue(unit, sig(b)) == nil
	end)
	if na:size() == 0 then return end
	-- Attached effects of the same source: by spell for spell-given ones, by stacking group for script-given ones
	local rm = unit:getBonuses({}):filter(function(b)
		if b:getType() == "NOT_ACTIVE" then return false end
		for i = 1, na:size() do
			local x = na:getBonus(i)
			if b:getSource() == x:getSource() and b:getSourceID() == x:getSourceID() then
				if x:getSource() == ENUM.BonusSource.spellEffect then return true end
				local st = x:getStacking()
				if st ~= nil and st ~= "" and b:getStacking() == st then return true end
			end
		end
		return false
	end)
	server:removeUnitBonuses(battle, unit, na)
	if rm:size() > 0 then Proxy.removeExact(server, battle, unit, rm) end
	server:refreshBattleUnits(battle)
	A.log(server, battle, 7, { A.name(unit) }, {})
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	clearTmp(server, battle, unit)
	if other == nil or not unit:isAlive() or not battle:isHostile(other, unit) then return end
	local flank = (not payload.ranged) and battle:isToReverse(other, unit, nil, nil)
	if flank then return end
	if A.markValue(unit, NF) == nil then snapshot(server, battle, unit) end
	A.setMark(server, battle, unit, NF, 1, 1)
	server:addUnitBonus(battle, unit, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = self.val or 9,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = TMP, hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	clearTmp(server, battle, unit)
	if A.markValue(unit, NF) ~= nil then stripIncap(server, battle, unit) end
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if A.markValue(unit, NF) == nil then return end
	stripIncap(server, battle, unit)
	A.clearMark(server, battle, unit, NF)
	clearSnapshot(server, battle, unit)
end

return Script
