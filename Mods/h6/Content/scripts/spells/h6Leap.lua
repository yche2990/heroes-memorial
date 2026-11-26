local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Spider Leap (H6 Namtaru): jumps to a position at least minRange hexes away where it fits; after landing all adjacent enemies take pct% of a normal attack each
--- (H3 formula, no counterattack). The AI automatically picks the landing spot with the most adjacent enemies. Parameters: pct, minRange, key, animation, sound

local function score(battle, caster, hex)
	-- Number of adjacent enemies when landing on hex (the ring around the hexes the caster occupies)
	local n = 0
	for _, u in ipairs(battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) end)) do
		local hs = u:getHexes()
		for i = 1, hs:size() do
			local d = L.hexDistance(hs:at(i), hex)
			if d <= 2 then n = n + 1; break end
		end
	end
	return n
end

function Script:validHex(mechanics, hex)
	local caster = mechanics:getUnitCaster()
	local battle = mechanics:getBattle()
	if caster == nil or hex == nil or not hex:isValid() then return false end
	if L.hexDistance(caster:getPosition(), hex) < (self.minRange or 3) then return false end
	return hex:isAvailable() and battle:isAccessibleForUnit(caster, hex)
end

function Script:best(mechanics)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local all = battle:getAllPossibleHexes()
	local best, bs = nil, 0
	for i = 1, all:size() do
		local h = all:at(i)
		if self:validHex(mechanics, h) then
			local s = score(battle, caster, h)
			if s > bs then best, bs = h, s end
		end
	end
	return best
end

function Script:applicableGeneral(mechanics, problem)
	if self:best(mechanics) == nil then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.hex and self:validHex(mechanics, dest.hex) then return true end
	end
	return self:best(mechanics) ~= nil
end

--- 2026-11-08 (AI skill fixes, review A2): when the clicked hex can be landed on, it comes first (apply takes the first hex it can land on),
--- followed by the enemies that will be hit after landing (within 1 hex of the landing hex; widened to 2 hexes for a two-hex caster, close to the "adjacent" range apply uses after landing),
--- so that the engine and the AI (BattleAI choosing where to drop location spells) can count the affected stacks; it used to return only hexes, so the Namtaru never used Spider Leap.
--- Hexes it cannot land on list no stacks (apply would then use best(), but the AI drops such hexes as "hits no enemy" when choosing, keeping only those it can land on)
function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local aim = aimPoint[1]
	if aim == nil or aim.hex == nil or not self:validHex(mechanics, aim.hex) then return spellTarget end
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local reach = caster:getHexes():size() > 1 and 2 or 1
	local list = { { hex = aim.hex } }
	for _, u in ipairs(battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) end)) do
		local hs = u:getHexes()
		for i = 1, hs:size() do
			if L.hexDistance(hs:at(i), aim.hex) <= reach then list[#list + 1] = { unit = u, hex = u:getPosition() }; break end
		end
	end
	return list
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local dest = nil
	for _, d in ipairs(target) do if d.hex and self:validHex(mechanics, d.hex) then dest = d.hex; break end end
	dest = dest or self:best(mechanics)
	if dest == nil then return end
	server:moveUnit(battle, caster, dest, true)
	local list = L.around(battle, caster, function(u) return battle:isHostile(caster, u) end)
	local total = 0
	for _, u in ipairs(list) do
		total = total + (L.hit(server, battle, u, L.attackDamage(server, caster, u, self.pct or 100, false), self.animation, self.sound) or 0)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 5, { L.name(caster) }, { #list, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Spider Leap: jumps to the target hex and strikes the enemies around where it lands
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorCharge" } -- step number -> cursor
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
