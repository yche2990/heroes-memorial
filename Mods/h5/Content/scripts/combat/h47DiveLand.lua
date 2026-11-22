local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Battle Dive, landing (H4-H7 mechanics port, round 129)
---
--- Added to the battlefield by spells/h47Dive at take-off. At the start of the next round (the first stack to trigger handles everything; later ones find no Griffin left to land):
--- damages the stack on the marked hex (friend or foe), removes the landing mark and puts the Griffin back on that hex; if the hex is occupied, on the nearest free hex.
--- Landing uses up the Griffin's action this round.
---
--- Damage: stack size x random damage (same as H3; above 10 creatures sampled as 10 and scaled up) x attack/defense modifier (+5% per point of higher attack, at most +300%;
--- higher Defense -2.5% per point, at most -70%) x factor. No luck, morale or other bonuses, no retaliation.
---
--- Parameters:
---   mark    name of this mod's hidden mark bonus (value = landing hex index + 1 + (take-off hex index + 1) x 1000; from round 153 the Griffin has no position while off the field)
---   spell   json name of the take-off spell, used to recognize its own landing marks
---   factor  damage multiplier

local W = 17

local function hexIndex(hex)
	return hex:getX() + hex:getY() * W
end

local function hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

local function allHexes(battle)
	local arr = battle:getAllPossibleHexes()
	local list = {}
	for i = 1, arr:size() do list[#list + 1] = arr:at(i) end
	return list
end

local function findHex(hexes, index)
	for _, hex in ipairs(hexes) do
		if hexIndex(hex) == index then return hex end
	end
	return nil
end

function Script:diveDamage(server, griffin, target)
	local count = griffin:getCount()
	local minDamage = griffin:getMinDamage(false)
	local maxDamage = math.max(minDamage, griffin:getMaxDamage(false))

	local base = 0
	if count <= 10 then
		for _ = 1, count do base = base + server:rngInt(minDamage, maxDamage) end
	else
		for _ = 1, 10 do base = base + server:rngInt(minDamage, maxDamage) end
		base = base * count / 10
	end

	local diff = griffin:getAttack(false) - target:getDefense(false)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end

	return math.max(1, math.floor(base * factor * (self.factor or 2)))
end

--- Hex nearest the landing hex where the Griffin fits
function Script:landingHex(battle, griffin, hexes, wanted, home)
	if wanted ~= nil and battle:isAccessibleForUnit(griffin, wanted) then return wanted end

	local origin = wanted or home
	if origin == nil then return nil end
	local best, bestDistance = nil, 1000
	for _, hex in ipairs(hexes) do
		if hex:isAvailable() and battle:isAccessibleForUnit(griffin, hex) then
			local d = hexDistance(hex, origin)
			if d < bestDistance then best, bestDistance = hex, d end
		end
	end
	return best
end

--- Round 153: whether the battle can continue after landing. If the enemy has no stacks left, or no stack besides this Griffin can act,
--- its action this round is not used up; otherwise the engine finds no stack to act this round and reports "Failed to find valid stack to act!"
function Script:battleGoesOn(battle, griffin, landingIds)
	local side = griffin:getSide()
	local enemies = battle:getUnitsIf(function(u)
		return u:getSide() ~= side and u:isAlive() and not u:isGhost() and not u:isTurret()
	end)
	if #enemies == 0 then return false end

	local myId = griffin:unitID()
	local others = battle:getUnitsIf(function(u)
		if u:unitID() == myId or not u:isAlive() then return false end
		if u:isGhost() and not landingIds[u:unitID()] then return false end
		return not u:hasBonuses({ type = "NOT_ACTIVE" })
	end)
	return #others > 0
end

function Script:onRoundStart(server, battle, unit, other)
	local airborne = battle:getUnitsIf(function(u)
		return u:isGhost() and u:isAlive() and u:hasBonuses({ type = self.mark })
	end)
	if #airborne == 0 then return end

	local hexes = allHexes(battle)
	local landings = {}

	for _, griffin in ipairs(airborne) do
		local marks = griffin:getBonuses({ type = self.mark })
		local v = marks:getBonus(1):getVal()
		local index = v % 1000 - 1
		local homeIndex = math.floor(v / 1000) - 1 -- Take-off hex; -1 for marks from old saves, which lack it
		server:removeUnitBonuses(battle, griffin, marks)

		local hex = findHex(hexes, index)
		if hex ~= nil then
			for _, obstacle in ipairs(battle:getObstaclesOnPos(hex, false)) do
				local spell = obstacle:getSpell()
				if spell ~= nil and spell:getJsonKey() == self.spell then
					server:removeObstacle(battle, obstacle)
				end
			end
		end

		local home = nil
		if homeIndex >= 0 then home = findHex(hexes, homeIndex) end
		if home == nil and griffin:getPosition():isValid() then home = griffin:getPosition() end

		landings[#landings + 1] = { griffin = griffin, hex = hex, home = home }
	end

	-- Settle the damage of all landing hexes first, then put the Griffins back (so a later Griffin does not land on an earlier one)
	for _, landing in ipairs(landings) do
		local griffin = landing.griffin
		local victim = landing.hex and battle:getUnitByPos(landing.hex, true)
		local name = griffin:getCreature():getNameTextID(griffin:getCount())

		if victim ~= nil and not victim:isGhost() and victim:isAlive() and not victim:isInvincible() then
			local damage = self:diveDamage(server, griffin, victim)
			local victimName = victim:getCreature():getNameTextID(victim:getCount())

			server:showBattleAnimation(battle, { { unit = victim } }, "h47/fx/fx_diveStrike", "ERTHQUAK", 1.0, true) -- Round 150: a dedicated dive impact animation (previously borrowed Dispel C05SPW)
			local dealt, killed = server:damageUnit(battle, victim, damage)

			server:appendLog(battle, {
				append         = { "core.bonus." .. self.mark .. ".description.2" },
				replaceStrings = { name, victimName },
				replaceNumbers = { dealt }
			})
			BattleLog.creaturesPerish(server, battle, victim, killed)
		else
			server:appendLog(battle, {
				append         = { "core.bonus." .. self.mark .. ".description.3" },
				replaceStrings = { name }
			})
		end
	end

	local landingIds = {}
	for _, landing in ipairs(landings) do landingIds[landing.griffin:unitID()] = true end

	for _, landing in ipairs(landings) do
		local griffin = landing.griffin
		local dest = self:landingHex(battle, griffin, hexes, landing.hex, landing.home) or landing.home
		if dest == nil then dest = battle:getAvailableHex(griffin:getCreature(), griffin:getSide(), nil) end

		local state = griffin:copy()
		state:setGhost(false)
		state:setPosition(dest)
		-- Landing uses up this round's action. The new engine dropped setMoved, so setFear stands in: its turn is skipped without a message and the effect clears next round
		if self:battleGoesOn(battle, griffin, landingIds) then state:setFear(true) end
		server:changeUnit(battle, state)
		-- Round 353d: changeUnit only changes the position, and the client still shows it on the takeoff hex (looking like it is there while it is actually at the landing spot, so it gets hit "from a distance");
		-- an in-place teleport moves the image to the landing hex
		pcall(function() server:moveUnit(battle, griffin, dest, true) end)
	end

	server:refreshBattleUnits(battle)

	for _, landing in ipairs(landings) do
		server:showBattleAnimation(battle, { { unit = landing.griffin } }, "h47/fx/fx_diveTakeoff", "TELPTIN", 1.0, true) server:refreshBattleUnits(battle) -- Round 150: a dedicated landing animation (previously borrowed Teleport C18SPW0)
	end
end

return Script
