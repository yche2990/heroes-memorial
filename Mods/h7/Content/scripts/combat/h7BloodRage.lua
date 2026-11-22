local Base = require("combat/combatScript")
local R = require("heroes-memorial.h7:combat/h7BloodRageLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 memorial Blood Rage (Stronghold racial skill, Yu's decision 2026-11-01). On every H7 Stronghold creature (not propagated).
--- With a hero on its side (no hero, no Blood Rage, except the Stronghold guards of the Memorial Sanctum: 6 at battle start), Blood Rage starts at 6, +3 at hero level 10 and +3 at level 20 (+2 more with Father Sky's Fury); the value is added to the Attack of the side's H7 Stronghold creatures.
--- -2 at the end of each round (applied at the start of the next round); -2 each time one of the side's H7 Stronghold creatures waits or defends; never below 0.
--- H7 Stronghold creatures are not affected by the Tears of Ashan Blood Rage (they are excluded with H7_BLOODRAGE_H7C). For Father Sky's Fury's "+2 when a stack is wiped out" see h7FatherSkyFury.lua.

local SKYFURY = "H7_SKYFURY_H7C"

function Script:onBattleStart(server, battle, unit, other, payload)
	if not R.isRager(unit) then return end
	local r = R.startValue(unit)
	if r <= 0 then return end -- No hero: no Blood Rage (except the Memorial Sanctum guards, given at battle start by h7SanctumTwin.lua, which must not be cleared here)
	if unit:hasBonuses({ type = SKYFURY }) then r = r + 2 end
	R.setOne(server, battle, unit, r)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if not R.isRager(unit) then return end
	local r = R.get(unit)
	if r > 0 then R.setOne(server, battle, unit, r - 2) end
end

function Script:drop(server, battle, unit)
	if not R.isRager(unit) then return end
	local r = R.sideValue(battle, unit:getSide())
	if r > 0 then R.setSide(server, battle, unit:getSide(), r - 2) end
end

function Script:onWait(server, battle, unit, other, payload)
	self:drop(server, battle, unit)
end

function Script:onDefend(server, battle, unit, other, payload)
	self:drop(server, battle, unit)
end

return Script
