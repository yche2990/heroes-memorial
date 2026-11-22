local Base = require("combat/combatScript")
local R = require("heroes-memorial.h7:combat/h7BloodRageLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- The 8th guard stack of the H7 Memorial Sanctum (heroes-memorial.h7:h7MemorialSanctum, gen_h7sanctum.py).
--- The engine allows at most 7 guard stacks for an object; the Sanctum guards are the upgraded creatures of levels 1-6 of one faction + one upgraded champion (champion A); the other upgraded champion (champion B,
--- same count) is added next to champion A by this script at battle start: not a summon, it counts toward victory and its losses count in the results.
--- This script is a hidden ability on all 14 upgraded champions (parameters twin = the other upgraded champion, army = upgraded creatures of levels 1-6 of that faction, comma-separated).
--- Only triggers when all of the following hold, which ordinary wandering monsters and hero armies never match exactly:
---   its side has no hero (no bonuses from a hero's primary skills, heroBaseSkill, on its stacks);
---   its side's stacks (alive, excluding summons, clones, arrow towers and war machines) are exactly 7: one each of the 6 kinds in army + this stack.
--- The added champion B carries this script too, but by then its side has 8 stacks, so nothing more is added.

local MOD = "heroes-memorial.h7:"

--- The added champion B missed the battle start (onBattleStart has already been sent), so its battle setup is done here (review R1: school immunity lists of Shadow/Black/Blaze Dragons,
--- the Fire Giant's Magma Blood, the Celestial Envoy's Pure Aura, settlement scripts of damage over time / stun), matched by script id (the subtype of COMBAT_EVENT_TRIGGER):
local function setupTwin(server, battle, u)
	local Imm = require("heroes-memorial.h7:combat/h7ImmuneLib")
	local St = require("heroes-memorial.h7:combat/h7StatusLib")
	local ok, list = pcall(function() return u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }) end)
	if not ok or list == nil then return end
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local sub = tostring(b:getSubtype() or "")
		local name = sub:match("([%w_]+)$") or sub
		local st = b:getStacking() or ""
		pcall(function()
			if name == "h7SchoolImmunity" or name == "h7MagicImmunity" then
				local school = st:match("^h7SchoolImmunity_(%w+)$") or "any"
				Imm.ensure(server, battle, u, "h7Imm|" .. school, Imm.debuffs(school))
			elseif name == "h7MagmaBlood" then
				Imm.ensure(server, battle, u, "h7Imm|fire", Imm.debuffs("fire"))
			elseif name == "h7AuraOfPurity" then
				require("heroes-memorial.h7:combat/h7AuraLib").refresh(server, battle)
			elseif name == "h7AcidDot" or name == "h7SweepingBash" or name == "h7WitheringVenom" then
				St.ensureTracker(server, battle, u)
			end
		end)
	end
end

local function bare(key)
	local i = key:find(":", 1, true)
	return i and key:sub(i + 1) or key
end

local function real(u, side)
	return u:isAlive() and u:getSide() == side and not u:isClone() and not u:copy():isSummoned() and not u:isTurret()
		and not u:hasBonuses({ type = "SIEGE_WEAPON" })
end

function Script:onBattleStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isClone() or unit:copy():isSummoned() then return end
	if type(self.twin) ~= "string" or type(self.army) ~= "string" then return end
	if unit:hasBonuses({ type = "PRIMARY_SKILL", sourceType = ENUM.BonusSource.heroBaseSkill }) then return end
	local side = unit:getSide()
	local need = {}
	for k in self.army:gmatch("[^,%s]+") do need[bare(k)] = 1 end
	need[bare(unit:getCreature():getJsonKey())] = 1
	local list = battle:getUnitsIf(function(u) return real(u, side) end)
	if #list ~= 7 then return end
	for _, u in ipairs(list) do
		local k = bare(u:getCreature():getJsonKey())
		if need[k] ~= 1 then return end
		need[k] = 0
	end
	for _, v in pairs(need) do
		if v ~= 0 then return end
	end
	local creature = LIBRARY:getCreatureByName(MOD .. bare(self.twin))
	if creature == nil then return end
	local hex = battle:getAvailableHex(creature, side, unit:getPosition())
	if hex == nil or not hex:isValid() then return end
	local added = server:addUnit(battle, {
		count    = unit:getCount(),
		type     = creature,
		side     = side,
		position = hex,
		summoned = false
	})
	if added == nil then return end
	setupTwin(server, battle, added)
	-- The Stronghold guards of the Memorial Sanctum (no hero) also have H7 Blood Rage: 6 at battle start (Yu's decision 2026-11-01); the added champion B gets it too
	if #R.sideRagers(battle, side) > 0 then R.setSide(server, battle, side, R.SANCTUM_START) end
	server:showBattleAnimation(battle, { { hex = hex } }, "C01SPE0", "", 0.6, true)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append = { "core.bonus.H7_SANCTUM_H7C.description.7" },
		replaceStrings = { creature:getNameTextID(unit:getCount()) },
		replaceNumbers = { unit:getCount() }
	})
end

return Script
