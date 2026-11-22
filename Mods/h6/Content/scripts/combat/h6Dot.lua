local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Damage over time settlement (H6 Pestilent Lamasu "Breath of Worms", Fate Spinner "Venomous Touch")
---
--- Hidden battle-wide bonus (BATTLE_WIDE): at the start of each round, stacks carrying H6_DOT_H6C take damage equal to the sum of these bonuses
--- (scaled by Earth and all-spell reduction; burning from Fiery Wrath counts as Fire, Dungeon dark damage over time as Dark). The bonuses are added by h6Lib.addDot and expire on their own.
--- Round 419: the share of a school the stack is immune to (SPELL_SCHOOL_IMMUNITY for that school or any) does not count.
--- Parameters: animation, sound

-- Source in the stacking name -> animation (longer names first: burnWorm must come before burn)
local ANIMS = {
	{ "burnWorm", "h6/boss/fx/lavaBurn" }, { "burn", "h6/stronghold/fx/burn" }, { "venom", "h6/necropolis/fx/venom" },
	{ "bleedVoid", "h6/boss/fx/rift" }, { "bleed", "h6/dungeon/fx/hit" }, { "zap", "h6/boss/fx/strike" }, { "dark", "h6/dungeon/fx/poison" },
}

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() then return end
	local list = unit:getBonuses({ type = "H6_DOT_H6C" })
	if list:size() == 0 then return end
	-- Round 351: scaled per source school (stacking names with burn are Fire, dark is Dark, bleed has no school, zap is Air, the rest Earth)
	local amount = 0
	local anim, best = nil, -1
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local key = b:getStacking() or ""
		local school = "earth"
		if string.find(key, "burn", 1, true) then school = "fire"
		elseif string.find(key, "dark", 1, true) then school = "02darkSchool"
		elseif string.find(key, "bleed", 1, true) then school = nil
		elseif string.find(key, "zap", 1, true) then school = "air" end
		-- Round 419: stacks immune to this school (or to all schools) do not take this share
		local immune = false
		if school then
			local ok, r = pcall(function()
				return unit:hasBonuses({ type = "SPELL_SCHOOL_IMMUNITY", subtype = "spellSchool." .. school })
					or unit:hasBonuses({ type = "SPELL_SCHOOL_IMMUNITY", subtype = "spellSchool.any" })
			end)
			immune = ok and r
		end
		if not immune then amount = amount + b:getVal() * (100 - L.schoolReduction(unit, school)) / 100 end
		-- Round 419: the damage-over-time sources share one stacking group and the engine keeps only one entry, so self.animation is not necessarily this share's; pick the animation by source (the share with the largest damage)
		if not immune and b:getVal() > best then
			best = b:getVal()
			for _, e in ipairs(ANIMS) do
				if string.find(key, e[1], 1, true) then anim = e[2]; break end
			end
		end
	end
	amount = math.floor(amount)
	if amount <= 0 then return end
	local dealt, killed = L.hit(server, battle, unit, amount, anim or self.animation, self.sound)
	L.log(server, battle, "H6_DOT_H6C", 1, { L.name(unit) }, { dealt or 0, killed or 0 })
end

return Script
