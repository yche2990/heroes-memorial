--- H6 memorial Blood Rage (battle-wide hidden script given to the hero by the Tears of Ashan Blood Rage skill; one per stacking group). Only a side that still has H6 Stronghold creatures on the field charges (Yu's decision: only H6 creatures).
--- Charging (original: "charges when troops attack, more for your own attacks"): whenever any stack takes damage (damage over time excluded), +16 for enemy losses and +8 for friendly losses. Damage from attacks and from hero and creature spells counts.
--- Automatic Blood Rage (Yu's decision: the original Blood Rage is automatic): at the start of each round, Blood Rage activates at the level matching the number of filled charge tiers (up to what the skill allows: Basic II, Advanced III, Expert IV),
--- spending that much charge; all H6 Stronghold creatures on its side get that Blood Rage level for this round (turns rounds) (h6RcLib.setRage); those already at a higher level (from Blood of Fury) are not lowered.
--- Parameters: animation, sound (followed by I to IV), turns
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local R = require("lib/h6RcLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local ROMAN = { "I", "II", "III", "IV" }

local function ragers(battle, side) return battle:getUnitsIf(function(u) return u:getSide() == side and R.isRager(u) end) end

local function charge(server, battle, unit)
	for _, side in ipairs({ 0, 1 }) do
		if R.sideEnabled(battle, side, "rage") and #ragers(battle, side) > 0 then
			R.addGauge(server, battle, side, "rage", unit:getSide() == side and 8 or 16)
		end
	end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not server:describeChanges() then return end
	local e = self:ownEntry(unit, payload)
	if e and (e.damage or 0) > 0 then charge(server, battle, unit) end
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if not server:describeChanges() then return end
	local e = self:ownEntry(unit, payload)
	if e and e.unitBefore and e.unitBefore:getAvailableHealth() > unit:getAvailableHealth() then charge(server, battle, unit) end
end

function Script:onRoundStart(server, battle, unit)
	if not server:describeChanges() then return end
	-- Review B4 (2026-11-08): this bonus is battle-wide, and the engine triggers it once for every living stack at round start;
	-- as in h6SpZoneTick, only the living stack with the lowest id settles, so each side's Blood Rage is settled once per round
	local first = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() end)) do
		if first == nil or u:unitID() < first then first = u:unitID() end
	end
	if unit == nil or first ~= unit:unitID() then return end
	local changed = false
	for _, side in ipairs({ 0, 1 }) do
		local units = ragers(battle, side)
		if #units > 0 and R.sideEnabled(battle, side, "rage") then
			local g = R.gauge(battle, side, "rage")
			local tier = math.min(R.rageMax(battle, side), math.floor(g / 100))
			if tier >= 1 then
				R.setGauge(server, battle, side, "rage", g - tier * 100)
				L.show(server, battle, units, self.animation, self.sound and (self.sound .. ROMAN[tier]) or nil)
				for _, u in ipairs(units) do
					local lv, turns = R.rageLevel(u)
					R.setRage(server, battle, u, math.max(lv, tier), math.max(self.turns or 1, turns))
				end
				L.log(server, battle, "H6_MM_STATUS_H6C", 9, {}, { tier })
				changed = true
			end
		end
	end
	if changed then server:refreshBattleUnits(battle) end
end

return Script
