--- Sacrifice (H6): after the protected stack is hit (attack or spell), the health it just lost is restored and the sacrificer takes it instead (reduced by reduce%).
--- Removed once the sacrificer is wiped out. Parameters: spell, partner (stack id of the sacrificer), reduce
--- "Already restored" convention (review A5 2026-11-08, see the healedValue section of combat/h6Lib): attack damage only transfers the part other scripts (shields, Ignore Pain, Feign Death...) have not restored yet,
--- and records the transferred amount in a MEMORIAL_MARK on the target (stacking "h6Healed|<attacker id>"); onBeforeAttacked clears these marks.
--- Spell damage is the difference between unitBefore and the current health, so earlier restores are already deducted. Several restoring effects together restore at most one share of the same hit.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function ring(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "HOTA_RING_OF_OBLIVION" }) end)
	return ok and v and v > 0
end

function Script:findPartner(battle)
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:unitID() == self.partner end)) do return u end
	return nil
end

--- Returns the amount transferred (restored)
function Script:transfer(server, battle, unit, lost)
	if lost <= 0 then return 0 end
	local p = self:findPartner(battle)
	if p == nil or not p:isAlive() then S.removeSpell(server, battle, unit, self.spell); return 0 end
	server:healUnit(battle, unit, lost, ring(unit) and ENUM.HealLevel.heal or ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	local dmg = math.floor(lost * (100 - (self.reduce or 33)) / 100)
	if dmg > 0 then
		local _, killed = server:damageUnit(battle, p, dmg)
		if server:describeChanges() then BattleLog.creaturesPerish(server, battle, p, killed) end
	end
	if not p:isAlive() then S.removeSpell(server, battle, unit, self.spell) end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	return lost
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	L.clearHealed(server, battle, unit)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local entry = self:ownEntry(unit, payload)
	if not entry then return end
	L.addHealed(server, battle, unit, other, self:transfer(server, battle, unit, L.unhealed(unit, other, entry.damage)))
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local entry = self:ownEntry(unit, payload)
	if not entry or not entry.unitBefore then return end
	self:transfer(server, battle, unit, entry.unitBefore:getAvailableHealth() - unit:getAvailableHealth())
end

return Script
