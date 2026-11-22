local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local L = require("spells/h7abLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Diving Attack, landing (H7 Royal Griffin, batch E)
---
--- Take-off uses the pack's spells/h47Dive (a byte-identical copy): choose a hex for the landing mark, the Griffin leaves the field, and this script is added to the battlefield
--- (addInfo = { mark, spell, factor }). Follows the pack's combat/h47DiveLand, changed to H7 rules:
---   at the start of the next round (the first stack to trigger handles everything) it dives onto the 2x2 area starting at the landing hex (landing hex, the hex to its right, the two hexes below),
---   and every stack in that area (friend or foe, invincible skipped) takes one hit:
---     stack size x random damage (above 10 creatures sampled as 10 and scaled up) x attack/defense modifier (Attack + factor; +5% per point of higher attack, at most +300%; -2.5% per point of higher defense, at most -70%),
---   with no counterattack; then it lands on the landing hex or the nearest free hex (back to the take-off hex if neither), using up this round's action.
--- Parameters (passed by h47Dive):
---   mark    name of the hidden mark bonus (value = landing hex index + 1 + (take-off hex index + 1) x 1000); value descriptions 1-3 are battle log texts
---   spell   json name of the take-off spell, used to recognize its own landing marks
---   factor  in this mod the "attack bonus when diving" (H7 +10, scaled by level 3 attack). In h47Dive it originally meant the damage multiplier

local STRIKE = "h7/fx/h7abDiveStrike"
local LANDING = "h7/fx/h7abDiveTakeoff"

local function findHex(hexes, index)
	return hexes[index]
end

local function square2x2(hex)
	local out = { hex }
	for _, d in ipairs({ "copyToEast", "copyToSouthWest", "copyToSouthEast" }) do
		local ok, h = pcall(function() return hex[d](hex) end)
		if ok and h ~= nil and h:isValid() then out[#out + 1] = h end
	end
	return out
end

--- Whether the battle can continue after landing (as the pack's round 153): if not, its action this round is not used up,
--- otherwise the engine finds no stack to act this round and reports "Failed to find valid stack to act!"
function Script:battleGoesOn(battle, griffin, landingIds)
	-- Hostility by battle:isHostile (hypnotized stacks count for their controller, review R1)
	local enemies = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and battle:isHostile(griffin, u)
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

--- Uses up this round's action: setMoved in older engines; newer engines (no setMoved since b145aff7) use setFear (skipped when its turn comes, cleared next round)
local function useTurn(state)
	if pcall(function() state:setMoved(true) end) then return end
	pcall(function() state:setFear(true) end)
end

function Script:onRoundStart(server, battle, unit, other)
	local airborne = battle:getUnitsIf(function(u)
		return u:isGhost() and u:isAlive() and u:hasBonuses({ type = self.mark })
	end)
	if #airborne == 0 then return end

	local hexes = L.hexTable(battle)
	local landings = {}

	for _, griffin in ipairs(airborne) do
		local marks = griffin:getBonuses({ type = self.mark })
		local v = marks:getBonus(1):getVal()
		local index = v % 1000 - 1
		local homeIndex = math.floor(v / 1000) - 1
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
		local home = (homeIndex >= 0) and findHex(hexes, homeIndex) or nil
		landings[#landings + 1] = { griffin = griffin, hex = hex, home = home }
	end

	-- Settle the damage of all landing hexes first, then put the Griffins back (so a later Griffin does not land on an earlier one)
	for _, landing in ipairs(landings) do
		local griffin = landing.griffin
		local victims, seen = {}, {}
		if landing.hex ~= nil then
			for _, h in ipairs(square2x2(landing.hex)) do
				local v = battle:getUnitByPos(h, true)
				if v ~= nil and not seen[v:unitID()] and v:unitID() ~= griffin:unitID() and not v:isGhost()
					and v:isAlive() and not v:isInvincible() then
					seen[v:unitID()] = true
					victims[#victims + 1] = v
				end
			end
		end
		for i, victim in ipairs(victims) do
			local damage = math.max(1, L.rollDamage(server, griffin, victim, self.factor or 0, 100, false))
			local victimName = L.name(victim)
			server:showBattleAnimation(battle, { { unit = victim } }, STRIKE, (i == 1) and "h7/h7ab_dive_end" or "", 1.0, true)
			local dealt, killed = server:damageUnit(battle, victim, damage)
			server:appendLog(battle, {
				append         = { "core.bonus." .. self.mark .. ".description.2" },
				replaceStrings = { L.name(griffin), victimName },
				replaceNumbers = { dealt }
			})
			BattleLog.creaturesPerish(server, battle, victim, killed)
		end
		if #victims == 0 then
			server:appendLog(battle, {
				append         = { "core.bonus." .. self.mark .. ".description.3" },
				replaceStrings = { L.name(griffin) }
			})
		end
	end

	local landingIds = {}
	for _, landing in ipairs(landings) do landingIds[landing.griffin:unitID()] = true end

	for _, landing in ipairs(landings) do
		local griffin = landing.griffin
		local dest = nil
		if landing.hex ~= nil then dest = L.nearestFree(battle, griffin, landing.hex) end
		if dest == nil and landing.home ~= nil then dest = L.nearestFree(battle, griffin, landing.home) end
		if dest == nil then dest = battle:getAvailableHex(griffin:getCreature(), griffin:getSide(), nil) end
		-- H7 audit B7: with a crowded battlefield and no free hex, getAvailableHex returns an invalid hex: it stays in the air and lands next round (no second strike, the landing hex recorded as "none")
		if dest == nil or not dest:isValid() then
			local homeIndex = landing.home and L.hexIndex and L.hexIndex(landing.home) or -1
			server:addUnitBonus(battle, griffin, {
				type = self.mark, val = (homeIndex + 1) * 1000, duration = "ONE_BATTLE",
				sourceType = "OTHER", hidden = true
			}, false)
		else

		local state = griffin:copy()
		state:setGhost(false)
		state:setPosition(dest)
		if self:battleGoesOn(battle, griffin, landingIds) then useTurn(state) end
		server:changeUnit(battle, state)
		-- Round 353d: changeUnit only changes the position, and the client still draws it on the take-off hex (it looks like it is there but is actually on the landing hex, and gets hit "through the air");
		-- an in-place teleport moves the image to the landing hex
		pcall(function() server:moveUnit(battle, griffin, dest, true) end)
		end
	end

	server:refreshBattleUnits(battle)

	for _, landing in ipairs(landings) do
		server:showBattleAnimation(battle, { { unit = landing.griffin } }, LANDING, "", 1.0, true)
		server:refreshBattleUnits(battle)
	end
end

return Script
