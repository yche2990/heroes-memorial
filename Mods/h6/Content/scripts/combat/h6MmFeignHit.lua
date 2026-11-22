--- Feign Death (H6 Memorial Sanctum, Dungeon): after a marked stack is attacked, this hit's damage is restored (killed creatures are saved too; with the Ring of Oblivion in play it only heals), the mark is removed,
--- and it temporarily cannot counterattack; when this action ends it leaves the battlefield (ghost state, no position), its hex is remembered, and combat/h6MmFeignEnd on the battlefield puts it back at the start of the next round.
--- A side's last stack on the battlefield does not fall (otherwise the battle would be judged over); it only gets the damage restored. Parameter: val (speed bonus after getting up)
--- If all other stacks on its side die while it is down, combat/h6MmFeignEnd on the battlefield makes it get up as soon as that action ends (review C2, 2026-11-08).
--- "Already restored" convention (review A5 2026-11-08, see the healedValue section of combat/h6Lib): only restores the part other scripts (shields, Sacrifice, Ignore Pain...) have not restored yet,
--- then records the amount in a MEMORIAL_MARK on the target (stacking "h6Healed|<attacker id>"); onBeforeAttacked clears these marks.
--- It still "falls" when other scripts have already restored everything (falling depends on being hit, not on how much was restored). Several restoring effects together restore at most one share of the same hit.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function ring(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "HOTA_RING_OF_OBLIVION" }) end)
	return ok and v and v > 0
end

local function others(battle, unit)
	local side, id = unit:getSide(), unit:unitID()
	return #battle:getUnitsIf(function(u)
		return u:unitID() ~= id and u:getSide() == side and u:isAlive() and not u:isGhost() and not u:isTurret()
			and not u:hasBonuses({ type = "SIEGE_WEAPON" })
	end)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	L.clearHealed(server, battle, unit)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if L.markValue(unit, "h6MmFeignDown") ~= nil then return end
	local entry = self:ownEntry(unit, payload)
	local dealt = entry and entry.damage or 0
	if dealt <= 0 then return end
	local rest = L.unhealed(unit, other, dealt)
	if rest > 0 then
		local level = ring(unit) and ENUM.HealLevel.heal or ENUM.HealLevel.resurrect
		server:healUnit(battle, unit, rest, level, ENUM.HealPower.permanent)
		L.addHealed(server, battle, unit, other, rest)
	end
	L.removeByStacking(server, battle, unit, "H6_MM_FEIGN_H6C", "h6MmFeign")
	L.log(server, battle, "H6_MM_STATUS_H6C", 3, { L.name(unit) }, {})
	if not unit:isAlive() or others(battle, unit) == 0 then
		L.removeByStacking(server, battle, unit, "COMBAT_EVENT_TRIGGER", "h6MmFeign")
		return
	end
	L.setMark(server, battle, unit, "h6MmFeignDown", L.hexIndex(unit:getPosition()) + 1)
	L.addBonus(server, battle, unit, { type = "NO_RETALIATION", val = 0, hidden = true, duration = ENUM.BonusDuration.nTurns, turns = 1,
		stacking = "h6MmFeignNoRet", sourceType = ENUM.BonusSource.other }, false)
end

--- Leaves only after this whole action (counterattack and second strike included) is over
function Script:onActionFinished(server, battle, unit, other, payload)
	local idx = L.markValue(unit, "h6MmFeignDown")
	if idx == nil or unit:isGhost() or not unit:isAlive() then return end
	if others(battle, unit) == 0 then
		L.clearMark(server, battle, unit, "h6MmFeignDown")
		L.removeByStacking(server, battle, unit, "COMBAT_EVENT_TRIGGER", "h6MmFeign")
		return
	end
	if server:describeChanges() then
		server:addBattleBonus(battle, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6MmFeignEnd", val = 0, duration = "ONE_BATTLE",
			sourceType = "OTHER", hidden = true, stacking = "h6MmFeignEnd" })
	end
	L.setMark(server, battle, unit, "h6MmFeignSpeed", self.val or 4)
	L.removeByStacking(server, battle, unit, "COMBAT_EVENT_TRIGGER", "h6MmFeign")
	local state = unit:copy()
	state:setGhost(true)
	state:setHadMorale(true)
	state:setPosition(-1)
	server:changeUnit(battle, state)
	server:refreshBattleUnits(battle)
end

return Script
