local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Necromancy (Heroes VII creatures and spells, based on h5NecroRaise.lua of heroes-memorial.h5; Yu's decision 2026-11-01)
--- When the hero's army has at least 4 stacks of H7 undead (this mod's Necropolis creatures with UNDEAD; real stacks present at battle start,
--- not summons or copies), Necromancy after winning this battle raises the matching H7 creatures: what would raise Skeletons raises
--- Skeletal Soldiers, and what skills, artifacts or specialties upgrade to other creatures raises the H7 creature of the same level and form (see MAP).
--- Creatures not in the table (Zombies and Mummies have no H7 counterpart; raise targets of other mods such as Death Valley or Crypt) are raised as usual. Counts follow the engine formula (converted by the new creature's health).
---
--- How the engine works (CGHeroInstance::calculateNecromancy): the values of all IMPROVED_NECROMANCY bonuses on the hero add up to
--- the necromancy power, and addInfo is the power required; among the entries with enough power it picks the creature of the highest level (the more expensive one at the same level). Necromancy is computed
--- when the battle result is settled, while the hero is still on the battlefield, so bonuses given to the hero during battle still apply.
--- At battle start this script:
---   1. reads the hero's current necromancy bonuses (through those this stack inherits) and works out each entry that has enough power;
---   2. gives the hero (propagator HERO, whole battle) each such entry replaced by the matching H7 creature (addInfo -1000000, usable at any power);
---   3. adds a negative necromancy power that pushes the power down to -1000, so every original entry with addInfo becomes unusable.
--- Necromancy entries without addInfo (the engine treats them as always usable) only come from mods outside this pack
--- (checked by h7mod/compat/patch_necro_addinfo.py: every creature on the left of MAP is also in the MAP of h5NecroRaise.lua;
--- those mods are not part of this release).
--- Each H7 undead stack carries one copy, and one stacking group counts once, so it does not matter which stack is removed.
--- An army has at most 7 stacks, so H5 and H7 can never both reach 4 stacks and the two scripts never work at the same time.

local THRESHOLD = 4                    -- Yu's decision: as for H5, at least 4 stacks
local PREFIX = "heroes-memorial.h7:"
local STACK = "h7NecroRaise_H7C"       -- Stacking prefix of this script's bonuses (used to skip our own when reading bonuses)
local DRAIN = 1000

-- Original raise target -> H7 creature. Basic to basic, first upgrade to upgraded; third forms (Tides of War gNec0x, third upgrades tum*) to the upgraded creature (H7 has no third forms).
-- The original Zombie line (walkingDead, zombieLord, gNec02, tumGhoul) and Mummies have no counterpart and are raised as usual (pending Yu's decision).
local MAP = {
	["core:skeleton"]        = "heroes-memorial.h7:h7NecropolisSkeleton",          -- Skeleton -> Skeletal Soldier
	["core:skeletonWarrior"] = "heroes-memorial.h7:h7NecropolisSkeletonHoplite",   -- Skeleton Warrior -> Skeletal Warrior
	["tidesofwar:gNec01"]    = "heroes-memorial.h7:h7NecropolisSkeletonHoplite",
	["core:wight"]           = "heroes-memorial.h7:h7NecropolisGhost",             -- Ghost -> Ghost
	["core:wraith"]          = "heroes-memorial.h7:h7NecropolisBanshee",           -- Wraith -> Lamenting Soul
	["tidesofwar:gNec03"]    = "heroes-memorial.h7:h7NecropolisBanshee",
	["core:vampire"]         = "heroes-memorial.h7:h7NecropolisVampire",
	["core:vampireLord"]     = "heroes-memorial.h7:h7NecropolisVampireLord",
	["tidesofwar:gNec04"]    = "heroes-memorial.h7:h7NecropolisVampireLord",
	["core:lich"]            = "heroes-memorial.h7:h7NecropolisLich",
	["core:powerLich"]       = "heroes-memorial.h7:h7NecropolisArchLich",
	["tidesofwar:gNec05"]    = "heroes-memorial.h7:h7NecropolisArchLich",
	["core:blackKnight"]     = "heroes-memorial.h7:h7NecropolisGrimRider",         -- Black Knight -> Spectral Rider
	["core:dreadKnight"]     = "heroes-memorial.h7:h7NecropolisGrimReaper",        -- Dread Knight -> Soul Reaper
	["tidesofwar:gNec06"]    = "heroes-memorial.h7:h7NecropolisGrimReaper",
	["core:boneDragon"]      = "heroes-memorial.h7:h7NecropolisBoneDragon",
	["core:ghostDragon"]     = "heroes-memorial.h7:h7NecropolisSpectralDragon",
	["tidesofwar:gNec07"]    = "heroes-memorial.h7:h7NecropolisSpectralDragon",
	-- Third forms of third-upgrades, like Tides of War gNec0x
	["third-upgrades:tumSkeletonKnight"] = "heroes-memorial.h7:h7NecropolisSkeletonHoplite",
	["third-upgrades:tumSpecter"]        = "heroes-memorial.h7:h7NecropolisBanshee",
	["third-upgrades:tumNosferatu"]      = "heroes-memorial.h7:h7NecropolisVampireLord",
	["third-upgrades:tumLichKing"]       = "heroes-memorial.h7:h7NecropolisArchLich",
	["third-upgrades:tumDeathKnight"]    = "heroes-memorial.h7:h7NecropolisGrimReaper",
}

local function hasType(u, t)
	local ok, r = pcall(function() return u:hasBonuses({ type = t }) end)
	return ok and r == true
end

--- Creature id: copies such as shrunk or downgraded versions read the data source mark (H7_SOURCE_H7C, stacking "h7Src|<source creature>"),
--- so shrunk or downgraded H7 creatures still count
local function sourceKey(u)
	local ok, list = pcall(function() return u:getBonuses({ type = "H7_SOURCE_H7C" }) end)
	if ok and list ~= nil then
		for i = 1, list:size() do
			local st = list:getBonus(i):getStacking() or ""
			if string.sub(st, 1, 6) == "h7Src|" then return string.sub(st, 7) end
		end
	end
	local c = u:getCreature()
	return c and c:getJsonKey() or ""
end

local function isH7Undead(u)
	if u:isClone() or u:isTurret() then return false end
	if u:copy():isSummoned() then return false end
	local key = sourceKey(u)
	if string.sub(key, 1, #PREFIX) ~= PREFIX then return false end
	return hasType(u, "UNDEAD")
end

local function normKey(s)
	if s == nil or s == "" then return nil end
	if string.find(s, ":", 1, true) == nil then return "core:" .. s end
	return s
end

local function ours(b)
	local s = b:getStacking() or ""
	return string.sub(s, 1, #STACK) == STACK
end

function Script:onBattleStart(server, battle, unit, other, payload)
	if not isH7Undead(unit) then return end
	local side = unit:getSide()
	local mine = battle:getUnitsIf(function(u) return u:getSide() == side and isH7Undead(u) end)
	if #mine < THRESHOLD then return end

	-- The hero's necromancy bonus (stacks inherit the hero's bonuses), minus what this script added
	local list = unit:getBonuses({ type = "IMPROVED_NECROMANCY" }):filter(function(b) return not ours(b) end)
	if list:size() == 0 then return end
	local power = list:totalValue()

	local targets, changed = {}, false
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local req = b:getParametersAsNumber() or 0
		local key = normKey(b:getSubtype())
		if key ~= nil and req <= power then
			local to = MAP[key]
			if to ~= nil and LIBRARY:getCreatureByName(to) ~= nil then
				changed = true
			else
				to = key
			end
			targets[to] = true
		end
	end
	if not changed then return end

	local src = unit:getCreature():getJsonKey()
	for to, _ in pairs(targets) do
		server:addUnitBonus(battle, unit, {
			type       = "IMPROVED_NECROMANCY",
			subtype    = to,
			val        = 0,
			propagator = "HERO",
			duration   = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other,
			sourceID   = src,
			addInfo    = -1000000,
			stacking   = STACK .. ":" .. to,
			hidden     = true
		}, false)
	end
	server:addUnitBonus(battle, unit, {
		type       = "IMPROVED_NECROMANCY",
		subtype    = "heroes-memorial.h7:h7NecropolisSkeleton",
		val        = -(power + DRAIN),
		addInfo    = 999999,
		propagator = "HERO",
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		sourceID   = src,
		stacking   = STACK .. ":drain",
		hidden     = true
	}, false)
end

return Script
