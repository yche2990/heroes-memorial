local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Heroes IV Necromancy (Heroes IV Creatures and Magic, after h7NecroRaise.lua of heroes-memorial.h7, round 587)
--- When the hero's army has at least 4 stacks of Heroes IV undead (this mod's creatures with UNDEAD: Skeleton, Ghost, Vampire, Bone Dragon, Zombie, Mummy, Dark Champion;
--- real stacks present at the start of battle, not summoned creatures or clones), Necromancy after a victory raises the corresponding Heroes IV creatures (see MAP).
--- Heroes IV has no upgrades, so the original base, upgrade and third form all map to the same H4 creature; the Lich line has no counterpart and is raised as before. Count follows the engine formula (converted by the new creature's health).
--- Done as in h7NecroRaise.lua (read the hero's raise bonuses -> swap for the H4 creature -> suppress the original entry with a negative value), with a different stacking prefix so they do not interfere.
--- An army has at most 7 stacks, so H4, H5 and H7 can never all have 4 stacks at once; the scripts never act together.

local THRESHOLD = 4                    -- Yu's decision: as for H5, at least 4 stacks
local PREFIX = "heroes-memorial.h4:"
local STACK = "h4NecroRaise_H4C"       -- Stacking prefix of this script's bonuses (used to skip our own when reading bonuses)
local DRAIN = 1000

-- Original raise target -> H7 creature. Basic to basic, first upgrade to upgraded; third forms (Tides of War gNec0x, third upgrades tum*) to the upgraded creature (H7 has no third forms).
-- The original Zombie line (walkingDead, zombieLord, gNec02, tumGhoul) and Mummies have no counterpart and are raised as usual (pending Yu's decision).
local MAP = {
	["core:skeleton"]        = "heroes-memorial.h4:h4Skeleton",
	["core:skeletonWarrior"] = "heroes-memorial.h4:h4Skeleton",
	["tidesofwar:gNec01"]    = "heroes-memorial.h4:h4Skeleton",
	["core:walkingDead"]     = "heroes-memorial.h4:h4Zombie",
	["core:zombieLord"]      = "heroes-memorial.h4:h4Zombie",
	["tidesofwar:gNec02"]    = "heroes-memorial.h4:h4Zombie",
	["core:wight"]           = "heroes-memorial.h4:h4Ghost",
	["core:wraith"]          = "heroes-memorial.h4:h4Ghost",
	["tidesofwar:gNec03"]    = "heroes-memorial.h4:h4Ghost",
	["core:vampire"]         = "heroes-memorial.h4:h4Vampire",
	["core:vampireLord"]     = "heroes-memorial.h4:h4Vampire",
	["tidesofwar:gNec04"]    = "heroes-memorial.h4:h4Vampire",
	["core:blackKnight"]     = "heroes-memorial.h4:h4DarkChampion",
	["core:dreadKnight"]     = "heroes-memorial.h4:h4DarkChampion",
	["tidesofwar:gNec06"]    = "heroes-memorial.h4:h4DarkChampion",
	["core:boneDragon"]      = "heroes-memorial.h4:h4BoneDragon",
	["core:ghostDragon"]     = "heroes-memorial.h4:h4BoneDragon",
	["tidesofwar:gNec07"]    = "heroes-memorial.h4:h4BoneDragon",
	["core:mummy"]           = "heroes-memorial.h4:h4Mummy",
	-- Third forms of third-upgrades, like Tides of War gNec0x
	["third-upgrades:tumSkeletonKnight"] = "heroes-memorial.h4:h4Skeleton",
	["third-upgrades:tumGhoul"]          = "heroes-memorial.h4:h4Zombie",
	["third-upgrades:tumSpecter"]        = "heroes-memorial.h4:h4Ghost",
	["third-upgrades:tumNosferatu"]      = "heroes-memorial.h4:h4Vampire",
	["third-upgrades:tumDeathKnight"]    = "heroes-memorial.h4:h4DarkChampion",
}

local function hasType(u, t)
	local ok, r = pcall(function() return u:hasBonuses({ type = t }) end)
	return ok and r == true
end

--- Creature ids: shrunk copies made by other mods read the source mark (hidden LUCK 0, stacking "h4Src|<source creature>"),
--- so shrunk Heroes IV creatures still count
local function sourceKey(u)
	local ok, list = pcall(function() return u:getBonuses({ type = "LUCK" }) end)
	if ok and list ~= nil then
		for i = 1, list:size() do
			local st = list:getBonus(i):getStacking() or ""
			if string.sub(st, 1, 6) == "h4Src|" then return string.sub(st, 7) end
		end
	end
	local c = u:getCreature()
	return c and c:getJsonKey() or ""
end

local function isH4Undead(u)
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
	if not isH4Undead(unit) then return end
	local side = unit:getSide()
	local mine = battle:getUnitsIf(function(u) return u:getSide() == side and isH4Undead(u) end)
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
		subtype    = "heroes-memorial.h4:h4Skeleton",
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
