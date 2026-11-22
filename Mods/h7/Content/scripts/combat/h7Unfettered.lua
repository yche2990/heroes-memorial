local Base = require("combat/combatScript")
local Imm = require("heroes-memorial.h7:combat/h7ImmuneLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Unfettered (Golem, Sandstone Golem, Crusher, Moon Stag, Sun Stag, Mauler, Shantiri Golem): immune to any kind of slowing.
--- 1. At battle start, SPELL_IMMUNITY against slowing spells (list h7ImmuneLib.SLOWS: core Slow, H7 Entangle, Blizzard etc., only those installed;
---    core Slow is also written in the creature JSON, so it shows in the creature window).
--- 2. Slowing from other spells, attack effects or scripts (negative STACKS_SPEED from spells or scripts):
---    removed when hit by a spell, when attacked, after each action and at the start of each round (e.g. the attached slowing of Ice Bolt and Ring of Winter, Time Control's slowing of enemies).

local KEY = "h7Imm|slow"

local function ensure(server, battle, unit)
	if not unit:isAlive() or unit:isGhost() then return end
	Imm.ensure(server, battle, unit, KEY, Imm.existing(Imm.SLOWS, true))
end

local function strip(server, battle, unit)
	if not unit:isAlive() then return end
	local list = unit:getBonuses({ type = "STACKS_SPEED" }):filter(function(b)
		local s = b:getSource()
		-- H7 audit B5: "Speed at most X" (an independent cap with a positive value, e.g. Electrified from Expert Lightning Burst) also counts as slowing
		local slow = b:getVal() < 0 or b:getValType() == ENUM.BonusValueType.independentMin
		return slow and (s == ENUM.BonusSource.spellEffect or s == ENUM.BonusSource.other)
	end)
	if list:size() > 0 then
		server:removeUnitBonuses(battle, unit, list)
		server:refreshBattleUnits(battle)
	end
end

function Script:onBattleStart(server, battle, unit) ensure(server, battle, unit) end

function Script:onRoundStart(server, battle, unit)
	ensure(server, battle, unit)
	strip(server, battle, unit)
end

function Script:onSpellHit(server, battle, unit) strip(server, battle, unit) end
function Script:onAfterAttacked(server, battle, unit) strip(server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other)
	if other ~= nil and other:unitID() == unit:unitID() then ensure(server, battle, unit) end
	strip(server, battle, unit)
end

return Script
