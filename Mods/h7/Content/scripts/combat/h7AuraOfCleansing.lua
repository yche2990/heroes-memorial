local Base = require("combat/combatScript")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Aura of Cleansing (Priest, Vestal)
--- Itself and adjacent allies Defense +val (original +4, scaled to +6 by level 4 Attack/Defense); at the start of each round, each sheltered stack has one random negative spell effect dispelled.
--- The original says "at the start of each stack's own turn"; the engine has no such event, so it happens at the start of each round instead (there are no negative spells at the start of round 1).
--- With several adjacent Priests only one is dispelled (deduplicated with a this-round mark).

local CLEANSE_ANIM = "h7/fx/h7Cleansing"
local DONE = "h7CleanseDone"

local function cleanseAll(server, battle)
	local units = battle:getUnitsIf(function(u) return A.real(u) and A.auraValue(u, "h7AuraOfCleansing") ~= nil end)
	for _, u in ipairs(units) do
		if A.markValue(u, DONE) == nil then
			A.setMark(server, battle, u, DONE, 1, 1)
			if A.dispelOneNegative(server, battle, u) then
				server:showBattleAnimation(battle, { { unit = u } }, CLEANSE_ANIM, "", 1.0, true)
				server:refreshBattleUnits(battle)
				A.log(server, battle, 1, { A.name(u) }, {})
			end
		end
	end
end

function Script:onBattleStart(server, battle, unit) A.refresh(server, battle) end

function Script:onRoundStart(server, battle, unit)
	A.refresh(server, battle)
	if unit:isAlive() then cleanseAll(server, battle) end
end

function Script:onDeath(server, battle, unit) A.refresh(server, battle) end

return Script
