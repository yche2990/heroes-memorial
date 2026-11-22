-- Gating (H5 Creatures and Magic): a patch on the summon effect core:summon.
-- When the casting side has at least 4 stacks of H5 demons on the field (this mod's creatures with Tears of Ashan's DEMONIC, not summoned creatures or copies),
-- the demons summoned by the Gating "Portal ..." spells (tears-of-ashan:gate*) are swapped for the corresponding H5 creatures, same count,
-- still summoned (vanishing after battle). See MAP for the table; creatures not in it are summoned unchanged.
-- How: the original spell is not changed; only the creature id to summon is swapped when the original summon logic is called (proxy table), so landing spot, count
-- and entrance animation (Tears of Ashan's toaSummonAppear hell portal) all go through the original code.
-- When the H5 creature takes two hexes and the original one, the landing spot is found for the new creature first; where the new one does not fit the original is summoned.
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local THRESHOLD = 4            -- Yu's decision: more than three stacks = at least 4 stacks
local PREFIX = "heroes-memorial.h5:"
-- Whether the count is converted by total health when swapping across levels (false = same count, Yu's words: "equal amount")
local SCALE_ACROSS_LEVELS = false

-- Original creature (getJsonKey) -> H5 creature. Base to base, upgrade to upgrade; by level when there is no same kind.
local MAP = {
	["core:imp"]                          = "heroes-memorial.h5:h5InfernoFamiliar",          -- Imp -> Devil Spawn
	["core:familiar"]                     = "heroes-memorial.h5:h5InfernoImp",               -- Familiar -> Imp
	["core:gog"]                          = "heroes-memorial.h5:h5InfernoDemon",             -- Gog (not in H5, by level 2) -> Horned Demon
	["core:magog"]                        = "heroes-memorial.h5:h5InfernoHornedDemon",       -- Magog -> Horned Overseer
	["core:hellHound"]                    = "heroes-memorial.h5:h5InfernoHellHound",         -- Hell Hound -> Hell Hound
	["core:cerberus"]                     = "heroes-memorial.h5:h5InfernoCerberius",         -- Cerberus -> Cerberus
	["core:demon"]                        = "heroes-memorial.h5:h5InfernoDemon",             -- Demon -> Horned Demon
	["core:hornedDemon"]                  = "heroes-memorial.h5:h5InfernoHornedDemon",       -- Horned Demon -> Horned Overseer
	["core:pitFiend"]                     = "heroes-memorial.h5:h5InfernoPitFiend",          -- Pit Fiend -> Pit Fiend
	["core:pitLord"]                      = "heroes-memorial.h5:h5InfernoBalor",             -- Pit Lord -> Pit Lord
	["core:efreet"]                       = "heroes-memorial.h5:h5InfernoPitFiend",          -- Efreet (not in H5, by level 6) -> Pit Fiend
	["core:efreetSultan"]                 = "heroes-memorial.h5:h5InfernoBalor",
	["core:devil"]                        = "heroes-memorial.h5:h5InfernoDevil",             -- Devil -> Devil
	["core:archDevil"]                    = "heroes-memorial.h5:h5InfernoArchDevil",         -- Arch Devil -> Arch Devil
	["wake-of-gods.creatures:hellSteed"]  = "heroes-memorial.h5:h5InfernoNightmare",         -- Hell Steed -> Hell Steed
	["wake-of-gods.creatures:nightmare"]  = "heroes-memorial.h5:h5InfernoFrightfulNightmare",-- Nightmare -> Nightmare
	["tidesofwar:mdtSukkub"]              = "heroes-memorial.h5:h5InfernoSuccubus",          -- Succubus -> Succubus
	["tidesofwar:mdtLilim"]               = "heroes-memorial.h5:h5InfernoInfernalSuccubus",  -- Lilim -> Succubus Mistress
}

local function isGating(mechanics)
	local spell = mechanics:getSpell()
	local key = spell and spell:getJsonKey() or ""
	return string.find(key, "tears-of-ashan:gate", 1, true) == 1
end

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

local function isH5Demon(u)
	if not u:isAlive() or u:isGhost() or u:isClone() or u:isTurret() then return false end
	if u:copy():isSummoned() then return false end
	local key = sourceKey(u)
	if string.sub(key, 1, #PREFIX) ~= PREFIX then return false end
	return hasType(u, "tears-of-ashan:DEMONIC") or hasType(u, "DEMONIC")
end

--- Returns (H5 creature, original creature) when the condition is met, otherwise nil
function Script:h5Replacement(mechanics)
	if not isGating(mechanics) then return nil end
	local orig = LIBRARY:getCreatureByName(self.id)
	if orig == nil then return nil end
	local target = MAP[orig:getJsonKey()]
	if target == nil then return nil end
	local h5 = LIBRARY:getCreatureByName(target)
	if h5 == nil then return nil end
	local side = mechanics:getCasterSide()
	local demons = mechanics:getBattle():getUnitsIf(function(u)
		return u:getSide() == side and isH5Demon(u)
	end)
	if #demons < THRESHOLD then return nil end
	return h5, orig
end

--- Proxy: only the creature id is swapped; other parameters (power, permanent, exclusive...) as the original spell
function Script:proxyFor(h5, orig)
	local proxy = setmetatable({ id = h5:getJsonKey() }, { __index = self })
	if SCALE_ACROSS_LEVELS and h5:getLevel() ~= orig:getLevel() then
		proxy.summonedCreatureAmount = function(p, mechanics)
			local n = self.summonedCreatureAmount(self, mechanics)
			return math.max(1, math.floor(n * orig:getMaxHealth() / h5:getMaxHealth()))
		end
		proxy.summonedCreatureHealth = function(p, mechanics)
			return p:summonedCreatureAmount(mechanics) * h5:getMaxHealth()
		end
	end
	return proxy
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local h5, orig = self:h5Replacement(mechanics)
	if h5 ~= nil then
		local res = Base.transformTarget(self:proxyFor(h5, orig), mechanics, aimPoint, spellTarget)
		if res ~= nil and #res > 0 then return res end
	end
	return Base.transformTarget(self, mechanics, aimPoint, spellTarget)
end

function Script:applicableGeneral(mechanics, problem)
	local h5, orig = self:h5Replacement(mechanics)
	if h5 ~= nil then
		return Base.applicableGeneral(self:proxyFor(h5, orig), mechanics, problem)
	end
	return Base.applicableGeneral(self, mechanics, problem)
end

function Script:apply(mechanics, server, target)
	local h5, orig = self:h5Replacement(mechanics)
	if h5 == nil then
		return Base.apply(self, mechanics, server, target)
	end
	local battle = mechanics:getBattle()
	local side = mechanics:getCasterSide()
	local proxy = self:proxyFor(h5, orig)
	for _, dest in ipairs(target) do
		local useH5
		if dest.unit ~= nil then
			useH5 = dest.unit:getCreature():getJsonKey() == h5:getJsonKey()
		else
			useH5 = dest.hex ~= nil and battle:isAccessibleForNewUnit(dest.hex, h5, side)
		end
		if useH5 then
			Base.apply(proxy, mechanics, server, { dest })
		else
			Base.apply(self, mechanics, server, { dest })
		end
	end
end

return Script
