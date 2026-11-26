local Base = require("spells/h47Dive")
local Proxy = require("lib/kadAiProxy")   -- AI simulation branch (ai-skills-design, as round 352)
local AI = require("spells/h7AiTrial")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Diving Attack of the H7 Imperial Griffin: the effect is exactly the collection's spells/h47Dive (that script is identical word for word in every mod and is not changed),
--- only the AI simulation branch is replaced. h47Dive's simulation estimates "the landing damage is factor times a normal attack", but in this mod factor is
--- "the Attack bonus of the dive" (landing script combat/h7DivingAttackLand); used as is, +20 Attack would be read as 20 times the damage.
--- Here it is estimated by H7 rules instead: all stacks in the 2x2 landing area (friend or foe) take one hit at Attack + factor x 0.6 (lands next round),
--- minus the action used up by the landing (see dive in spells/h7AiTrial). Real casts still go through h47Dive.

local function square2x2(hex)
	local out = { hex }
	for _, d in ipairs({ "copyToEast", "copyToSouthWest", "copyToSouthEast" }) do
		local ok, h = pcall(function() return hex[d](hex) end)
		if ok and h ~= nil and h:isValid() then out[#out + 1] = h end
	end
	return out
end

function Script:apply(mechanics, server, target)
	if Proxy.trial(server) then
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		local d = target and target[1]
		if caster == nil or not caster:isAlive() or d == nil or d.hex == nil or not d.hex:isValid() then return end
		AI.dive(server, battle, caster, square2x2(d.hex), self.factor or 0)
		return
	end
	return Base.apply(self, mechanics, server, target)
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Dive Attack (H7 Imperial Griffin)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorDive" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
