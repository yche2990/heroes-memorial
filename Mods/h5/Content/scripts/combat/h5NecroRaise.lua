local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Necromancy (H5 Creatures and Magic)
--- When the hero's army has at least 4 stacks of H5 undead (this mod's creatures with UNDEAD; real stacks present at the start of battle,
--- not summoned creatures or clones), Necromancy after a victory raises the corresponding H5 creatures: what would raise Skeletons raises
--- H5 Skeletons, what is upgraded to other creatures by skills, artifacts or specialties raises the H5 creature of the same level and form (see MAP).
--- Creatures not in the table (raise targets of other mods such as Necropolis Valley or Crypt) are raised as before. Count follows the engine formula (converted by the new creature's health).
---
--- How the engine works (CGHeroInstance::calculateNecromancy): the values of all IMPROVED_NECROMANCY bonuses on the hero add up to
--- the necromancy power, and addInfo is the power required; among the entries with enough power it picks the creature of the highest level (the more expensive one at the same level). Necromancy is computed
--- when the battle result is settled, while the hero is still on the battlefield, so bonuses given to the hero during battle still apply.
--- At battle start this script:
---   1. reads the hero's current necromancy bonuses (through those this stack inherits) and works out each entry that has enough power;
---   2. Added to the hero (propagator HERO, whole battle): each entry replaced by the corresponding H5 creature (addInfo -1000000, usable however low the power);
---   3. adds a negative necromancy power that pushes the power down to -1000, so every original entry with addInfo becomes unusable.
--- the engine then picks the strongest among the entries of step 2 by its usual rule. When the battle ends (the army node is removed) these bonuses go with it.
--- Raise entries without addInfo: the engine treats them as always usable (calculateNecromancy: empty bonus->parameters skip the power check), so step 3 cannot suppress them.
--- Lua cannot remove bonuses on the hero (from artifacts, specialties, buildings) and mod scripts have no post-battle hook, so it is solved in the data instead:
--- compat/patch_necro_addinfo.py gives entries of this kind whose target is in MAP (the mystic skill artifact of the third-upgrade archer version, the combined artifact Death Valley)
--- addInfo 0 (needs 0 power, normally no change in effect), so step 3 can disable them too; step 1 treats entries without addInfo as needing 0 power
--- and adds them back as the corresponding creature. Those whose target is not in MAP (Necropolis Valley's Grail gghost, demon raising etc.) are added back with their original target; patched or not makes no difference.
--- Each H5 undead stack carries one copy, one per stacking group, so removing any one stack does not matter.

local THRESHOLD = 4                    -- Yu's decision: more than three stacks = at least 4 stacks
local PREFIX = "heroes-memorial.h5:"
local STACK = "h5NecroRaise_H5C"       -- Stacking prefix of this script's bonuses (used to skip our own when reading bonuses)
local DRAIN = 1000

-- Original raise target -> H5 creature. Base to base, first upgrade to first upgrade, third form (Tide gNec0x) to third form.
local MAP = {
	["core:skeleton"]        = "heroes-memorial.h5:h5NecropolisSkeleton",            -- Skeleton -> Skeleton
	["core:skeletonWarrior"] = "heroes-memorial.h5:h5NecropolisSkeletonArcher",      -- Skeleton Warrior -> Skeleton Archer (first upgrade)
	["tidesofwar:gNec01"]    = "heroes-memorial.h5:h5Necropolis3rdSkeletonWarrior",  -- Third form -> Skeleton Warrior
	["core:walkingDead"]     = "heroes-memorial.h5:h5NecropolisWalkingDead",
	["core:zombieLord"]      = "heroes-memorial.h5:h5NecropolisZombie",
	["tidesofwar:gNec02"]    = "heroes-memorial.h5:h5Necropolis3rdDiseaseZombie",
	["core:wight"]           = "heroes-memorial.h5:h5NecropolisManes",
	["core:wraith"]          = "heroes-memorial.h5:h5NecropolisGhosts",
	["tidesofwar:gNec03"]    = "heroes-memorial.h5:h5Necropolis3rdPoltergeist",
	["core:vampire"]         = "heroes-memorial.h5:h5NecropolisVampire",
	["core:vampireLord"]     = "heroes-memorial.h5:h5NecropolisVampireLord",
	["tidesofwar:gNec04"]    = "heroes-memorial.h5:h5Necropolis3rdNosferatu",
	["core:lich"]            = "heroes-memorial.h5:h5NecropolisLich",
	["core:powerLich"]       = "heroes-memorial.h5:h5NecropolisDemilich",
	["tidesofwar:gNec05"]    = "heroes-memorial.h5:h5Necropolis3rdLichMaster",
	["core:blackKnight"]     = "heroes-memorial.h5:h5NeutralsBlackKnight",
	["core:dreadKnight"]     = "heroes-memorial.h5:h5NeutralsDeathKnight",
	["tidesofwar:gNec06"]    = "heroes-memorial.h5:h5NeutralsDeathKnight",
	["core:boneDragon"]      = "heroes-memorial.h5:h5NecropolisBoneDragon",
	["core:ghostDragon"]     = "heroes-memorial.h5:h5NecropolisShadowDragon",
	["tidesofwar:gNec07"]    = "heroes-memorial.h5:h5Necropolis3rdHorrorDragon",
	["core:mummy"]           = "heroes-memorial.h5:h5NeutralsMummy",
	-- Third forms of third-upgrades, like Tides of War gNec0x
	["third-upgrades:tumSkeletonKnight"] = "heroes-memorial.h5:h5Necropolis3rdSkeletonWarrior",
	["third-upgrades:tumGhoul"]          = "heroes-memorial.h5:h5Necropolis3rdDiseaseZombie",
	["third-upgrades:tumSpecter"]        = "heroes-memorial.h5:h5Necropolis3rdPoltergeist",
	["third-upgrades:tumNosferatu"]      = "heroes-memorial.h5:h5Necropolis3rdNosferatu",
	["third-upgrades:tumLichKing"]       = "heroes-memorial.h5:h5Necropolis3rdLichMaster",
	["third-upgrades:tumDeathKnight"]    = "heroes-memorial.h5:h5NeutralsDeathKnight",
}

local function hasType(u, t)
	local ok, r = pcall(function() return u:hasBonuses({ type = t }) end)
	return ok and r == true
end

--- Creature ids: copied creatures such as shrunk or downgraded versions read the source mark (H5_SOURCE_H5C, stacking "h5Src|<source creature>", see h5Common.sourceKey),
--- so shrunk or downgraded H5 creatures still count
local function sourceKey(u)
	local ok, list = pcall(function() return u:getBonuses({ type = "H5_SOURCE_H5C" }) end)
	if ok and list ~= nil then
		for i = 1, list:size() do
			local st = list:getBonus(i):getStacking() or ""
			if string.sub(st, 1, 6) == "h5Src|" then return string.sub(st, 7) end
		end
	end
	local c = u:getCreature()
	return c and c:getJsonKey() or ""
end

local function isH5Undead(u)
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
	if not isH5Undead(unit) then return end
	local side = unit:getSide()
	local mine = battle:getUnitsIf(function(u) return u:getSide() == side and isH5Undead(u) end)
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
		subtype    = "heroes-memorial.h5:h5NecropolisSkeleton",
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
