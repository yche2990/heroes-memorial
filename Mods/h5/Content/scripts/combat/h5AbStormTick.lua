local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local C = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Settling of the Storm Lord's thundercloud (attached to the battlefield by spells/h5AbZone when the cloud is placed). At the start of each round (the first stack triggered handles all):
---   stacks in the cloud (the hexes of the thundercloud obstacle) take Storm Lord count x per Air damage;
---   shooters in the cloud deal -min(Storm Lord count x 1%, maxPenalty%) ranged damage this round.
--- Parameters: spell (full name of the cloud spell), power (Storm Lord count at cast time), per, maxPenalty, center (round 375: center hex of this cloud), caster (casting stack id, not hit)

function Script:onRoundStart(server, battle, unit, other, payload)
	local spell = LIBRARY:getSpellByName(self.spell)
	if spell == nil then return end
	local key = spell:getJsonKey()
	-- Settled only once per round: only by the living stack with the lowest id
	local first = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() end)) do
		if first == nil or u:unitID() < first then first = u:unitID() end
	end
	if first ~= unit:unitID() then return end

	-- Round 375: each side's clouds are settled separately (h5AbZone attaches one per side, addInfo holds this cloud's center hex and caster):
	-- only its own cloud (within 1 hex of the center) is settled, and the casting Storm Lord itself is not hit (all clouds used to share one count, and hit the caster too)
	local center = nil
	if self.center ~= nil then
		local ci = self.center
		center = { getX = function() return ci % C.W end, getY = function() return math.floor(ci / C.W) end }
	end
	local hit = {}
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		local s = o:getSpell()
		if s ~= nil and s:getJsonKey() == key and (center == nil or C.hexDistance(o:getPosition(), center) <= 1) then
			local u = battle:getUnitByPos(o:getPosition(), true)
			if u ~= nil and self.caster ~= nil and u:unitID() == self.caster then u = nil end
			if u ~= nil and not hit[u:unitID()] and u:isAlive() and not u:isGhost() and not u:isInvincible() then
				hit[u:unitID()] = true
				local power = self.power or 1
				local raw = power * (self.per or 10)
				local dmg = raw
				local ok, adj = pcall(function() return spell:adjustDamage(battle, u, u, raw) end)
				if ok and type(adj) == "number" then dmg = adj end
				if dmg > 0 then
					server:showBattleAnimation(battle, { { unit = u } }, "h5/fx/fx_blank", "LIGHTBLT", 1.0, true)
					local _, killed = server:damageUnit(battle, u, dmg)
					BattleLog.creaturesPerish(server, battle, u, killed)
				end
				if u:isAlive() and u:isShooter() then
					local pct = math.min(power, self.maxPenalty or 90)
					C.removeByStacking(server, battle, u, "PERCENTAGE_DAMAGE_BOOST", "h5AbStormPenalty")
					server:addUnitBonus(battle, u, {
						type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeRanged", val = -pct,
						duration = ENUM.BonusDuration.nTurns, turns = 1, sourceType = ENUM.BonusSource.spellEffect,
						sourceID = key, sourceSecondaryID = 0, stacking = "h5AbStormPenalty" --[[ Round 339: since engine 89ce99f1, omitting the casting level means "any level", and looking at a stack's spell status reads the description with that level out of range, giving garbage (log: Unable to find localization); the level is stated ]]
					}, true)
				end
			end
		end
	end
	server:refreshBattleUnits(battle)
end

return Script
