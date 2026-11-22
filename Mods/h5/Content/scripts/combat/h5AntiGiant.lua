local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Giant Slayer (Battlerager): Attack +attack and Defense +defence when fighting large (two-hex) creatures.
--- Before striking and before being attacked it checks whether the other is two-hex; if so the bonus is attached, removed when the exchange ends. Parameters: attack, defence

local STACK = "h5AntiGiant"

local function clear(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "PRIMARY_SKILL", STACK)
end

local function big(u)
	return u ~= nil and u:getCreature():isDoubleWide()
end

function Script:apply(server, battle, unit, foe)
	clear(server, battle, unit)
	if not big(foe) then return end
	local src = unit:getCreature():getJsonKey()
	for _, p in ipairs({ { "primarySkill.attack", self.attack or 4 }, { "primarySkill.defence", self.defence or 4 } }) do
		server:addUnitBonus(battle, unit, {
			type = "PRIMARY_SKILL", subtype = p[1], val = p[2],
			duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = STACK, hidden = true
		}, true)
	end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	local entry = H5.firstTarget(payload)
	self:apply(server, battle, unit, entry and entry.unit)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	self:apply(server, battle, unit, other)
end

function Script:onAfterAttack(server, battle, unit, other, payload) clear(server, battle, unit) end
function Script:onAfterAttacked(server, battle, unit, other, payload) clear(server, battle, unit) end

return Script
