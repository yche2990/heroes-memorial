local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H6 Necromancy (H6 creatures and spells; based on the scripts of the same name in the H6 and H5 memorials, merged in round 418)
--- When the hero's army has at least 4 stacks of H6 undead (creatures of this mod with UNDEAD; real stacks present at battle start, not summons or clones),
--- Necromancy after winning this battle raises the matching H6 creatures (see MAP): Skeletons, the Zombie line (H6 Ghouls), Ghosts, Vampires, Liches, Ghost Dragons.
--- Creatures not in the table (Black Knights, Dread Knights, Bone Dragons and Mummies have no H6 counterpart; raise targets of other mods such as Death Valley or Crypt) are raised as usual.
--- How the engine works and how entries without addInfo are handled: same as the necromancy script of heroes-memorial.h5.
--- Each H6 undead stack carries one copy; one stacking group counts once. An army has at most 7 stacks, so H5, H6 and H7 can never all reach 4 stacks at once.

local THRESHOLD = 4                    -- Yu's decision: as for H5 and H7, at least 4 stacks
local PREFIX = "heroes-memorial.h6:"
local STACK = "h6NecroRaise_H6C"       -- Stacking prefix of this script's bonuses (used to skip our own when reading bonuses)
local DRAIN = 1000

-- Original raise target -> H6 creature. Basic to basic, upgraded to upgraded; third forms (Tides of War gNec0x, third upgrades tum*) to the upgraded creature (H6 has no third forms).
-- The Black Knight line, Bone Dragons and Mummies have no H6 counterpart and are raised as usual.
local MAP = {
	["core:skeleton"]         = "heroes-memorial.h6:h6NecroSkeleton",  -- Skeleton -> Skeleton
	["core:skeletonWarrior"]  = "heroes-memorial.h6:h6NecroSkeletalSpearman",  -- Skeleton Warrior -> Skeleton Spearman
	["tidesofwar:gNec01"]     = "heroes-memorial.h6:h6NecroSkeletalSpearman",
	["core:walkingDead"]      = "heroes-memorial.h6:h6NecroGhoul",  -- Zombie -> Ghoul (H6 level 2 undead)
	["core:zombieLord"]       = "heroes-memorial.h6:h6NecroRavenous",  -- Zombie Lord -> Ravenous Ghoul
	["tidesofwar:gNec02"]     = "heroes-memorial.h6:h6NecroRavenous",
	["core:wight"]            = "heroes-memorial.h6:h6NecroGhost",  -- Ghost -> Ghost
	["core:wraith"]           = "heroes-memorial.h6:h6NecroSpectre",  -- Wraith -> Spectre
	["tidesofwar:gNec03"]     = "heroes-memorial.h6:h6NecroSpectre",
	["core:vampire"]          = "heroes-memorial.h6:h6NecroVampire",
	["core:vampireLord"]      = "heroes-memorial.h6:h6NecroVampireLord",
	["tidesofwar:gNec04"]     = "heroes-memorial.h6:h6NecroVampireLord",
	["core:lich"]             = "heroes-memorial.h6:h6NecroLich",  -- Lich -> Lich
	["core:powerLich"]        = "heroes-memorial.h6:h6NecroArchlich",  -- Power Lich -> Lich Master
	["tidesofwar:gNec05"]     = "heroes-memorial.h6:h6NecroArchlich",
	["core:ghostDragon"]      = "heroes-memorial.h6:h6NeutralSpectralDragon",  -- Ghost Dragon -> Spectral Dragon
	["tidesofwar:gNec07"]     = "heroes-memorial.h6:h6NeutralSpectralDragon",
	-- Third forms of third-upgrades, like Tides of War gNec0x
	["third-upgrades:tumSkeletonKnight"] = "heroes-memorial.h6:h6NecroSkeletalSpearman",
	["third-upgrades:tumGhoul"] = "heroes-memorial.h6:h6NecroRavenous",
	["third-upgrades:tumSpecter"] = "heroes-memorial.h6:h6NecroSpectre",
	["third-upgrades:tumNosferatu"] = "heroes-memorial.h6:h6NecroVampireLord",
	["third-upgrades:tumLichKing"] = "heroes-memorial.h6:h6NecroArchlich",
}


local function hasType(u, t)
	local ok, r = pcall(function() return u:hasBonuses({ type = t }) end)
	return ok and r == true
end

--- Creature id: copies such as shrunk or downgraded versions read the data source mark (H6_SOURCE_H6C, stacking "h6Src|<source creature>"),
--- so shrunk or downgraded H6 creatures still count
local function sourceKey(u)
	local ok, list = pcall(function() return u:getBonuses({ type = "H6_SOURCE_H6C" }) end)
	if ok and list ~= nil then
		for i = 1, list:size() do
			local st = list:getBonus(i):getStacking() or ""
			if string.sub(st, 1, 6) == "h6Src|" then return string.sub(st, 7) end
		end
	end
	local c = u:getCreature()
	return c and c:getJsonKey() or ""
end

local function isH6Undead(u)
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
	if not isH6Undead(unit) then return end
	local side = unit:getSide()
	local mine = battle:getUnitsIf(function(u) return u:getSide() == side and isH6Undead(u) end)
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
		subtype    = "heroes-memorial.h6:h6NecroSkeleton",
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
