--- Celestial Armor (H6): absorbs pct% of the damage taken until full (the remaining amount is in a hidden mark written at cast time). Attack and spell damage is restored by the absorbed amount after it lands
--- (creatures killed by this hit are saved too; with the Ring of Oblivion in play it only heals, no resurrection). When full, all effects of this spell are removed. Parameters: pct, spell, key (mark name)
--- "Already restored" convention (review A5 2026-11-08, see the healedValue section of combat/h6Lib): attack damage only absorbs the part other scripts have not restored yet,
--- then records the absorbed amount in a MEMORIAL_MARK on the target (stacking "h6Healed|<attacker id>"); onBeforeAttacked clears these marks.
--- Spell damage is the difference between unitBefore and the current health, so earlier restores are already deducted. Several restoring effects together restore at most one share of the same hit.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function ring(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "HOTA_RING_OF_OBLIVION" }) end)
	return ok and v and v > 0
end

--- dealt: damage of this hit not yet restored; full: all damage of this hit (pct% is taken of it). Returns the absorbed amount
function Script:absorb(server, battle, unit, dealt, full)
	if dealt <= 0 then return 0 end
	local left = L.markValue(unit, self.key) or 0
	if left <= 0 then return 0 end
	local take = math.min(left, dealt, math.floor((full or dealt) * (self.pct or 100) / 100))
	if take <= 0 then return 0 end
	local level = ring(unit) and ENUM.HealLevel.heal or ENUM.HealLevel.resurrect
	server:healUnit(battle, unit, take, level, ENUM.HealPower.permanent)
	left = left - take
	if left <= 0 then
		L.clearMark(server, battle, unit, self.key)
		S.removeSpell(server, battle, unit, self.spell)
	else
		L.setMark(server, battle, unit, self.key, left)
	end
	return take
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	L.clearHealed(server, battle, unit)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local entry = self:ownEntry(unit, payload)
	if not entry then return end
	local damage = entry.damage or 0
	local take = self:absorb(server, battle, unit, L.unhealed(unit, other, damage), damage)
	L.addHealed(server, battle, unit, other, take)
end

function Script:onSpellHit(server, battle, unit, other, payload)
	local entry = self:ownEntry(unit, payload)
	if not entry or not entry.unitBefore then return end
	-- Not yet restored = health before the cast - current health (what earlier scripts restored is already deducted); the absorbed share is based on the whole damage of the hit, entry.damage
	self:absorb(server, battle, unit, entry.unitBefore:getAvailableHealth() - unit:getAvailableHealth(), entry.damage)
end

return Script
