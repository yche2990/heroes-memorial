local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local E = require("heroes-memorial.h7:combat/h7EarthLib")
local Cloud = require("heroes-memorial.h7:spells/h7PoisonCloud")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Area of Poison Cloud (H7) (added to the battlefield by the spell spells/h7PoisonCloud; every stack on the battlefield carries it).
--- The area's state is the poison mist obstacles on the field: one per hex; at cast time the center + one ring (turns rounds left), then one more ring at the start of each round,
--- each new ring with the same remaining rounds as the old ones, all removed together by the engine on expiry; when the mist on the center hex is gone, this cloud is over.
--- At the start of each round (the first stack to trigger settles once for the whole battlefield, with a this-round mark on all stacks to avoid repeats):
---   grow one ring (up to ring 3 = H7's 7x7), then stacks in the cloud take val Earth damage (the casting side's hero bonuses and the target's resistance applied separately).
--- A stack that stops in the cloud after moving (H7 says "entering the cloud"; VCMI only knows the end point) also takes damage.
--- Each stack takes cloud damage at most once per round (mark h7PoisonCloudHit, 1 round).
--- Parameters: center (center hex index), side (casting side), spell, turns, animation (persistent mist), hitAnimation, hitSound; val = raw damage

function Script:radius(battle, hexes)
	local center = hexes[self.center]
	if center == nil then return -1 end
	local r = -1
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		local s = o:getSpell()
		if s ~= nil and s:getJsonKey() == self.spell then
			local d = E.hexDistance(o:getPosition(), center)
			if d <= 3 and d > r then r = d end
			if d == 0 and r < 0 then r = 0 end
		end
	end
	-- The mist on the center hex is gone: this cloud is over
	local alive = false
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		local s = o:getSpell()
		if s ~= nil and s:getJsonKey() == self.spell and E.hexDistance(o:getPosition(), center) == 0 then alive = true break end
	end
	if not alive then return -1 end
	return r, center
end

function Script:hurt(server, battle, list)
	local fresh = {}
	for _, u in ipairs(list) do
		if E.markVal(u, Cloud.HIT) == nil then fresh[#fresh + 1] = u end
	end
	if #fresh == 0 then return end
	E.anim(server, battle, fresh, self.hitAnimation or "", self.hitSound or "", true)
	for _, u in ipairs(fresh) do
		local amount = E.spellDamage(battle, self.spell, self.side, u, (self.val or 0) * (self.bonus or 100) / 100) -- H7 audit B1
		if amount > 0 then
			local _, killed = server:damageUnit(battle, u, amount)
			BattleLog.creaturesPerish(server, battle, u, killed)
		end
		if u:isAlive() then E.setMark(server, battle, u, Cloud.HIT, 1, 1) end
	end
end

function Script:roundTag()
	return "h7PCRound" .. tostring(self.center) .. "_" .. tostring(self.group or 0) -- H7 audit B3: kept apart by cloud id
end

function Script:onRoundStart(server, battle, unit, other, payload)
	local tag = self:roundTag()
	local done = battle:getUnitsIf(function(u) return u:isAlive() and E.markVal(u, tag) ~= nil end)
	if #done > 0 then return end
	local hexes = E.hexTable(battle)
	local r, center = self:radius(battle, hexes)
	if r < 0 then return end

	local everyone = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() end)
	for _, u in ipairs(everyone) do E.setMark(server, battle, u, tag, 1, 1) end

	if r < 3 then
		local spell = LIBRARY:getSpellByName(self.spell)
		local left = (self.turns or 3) - r
		if left >= 1 then
			Cloud.addRing(server, battle, spell, self.side, center, r + 1, r + 1, left, self.animation)
			r = r + 1
		end
	end

	local list = battle:getUnitsIf(function(u)
		return not Cloud.cloudImmune(u, self.spell) and E.unitHexDistance(u, center) <= r
	end)
	self:hurt(server, battle, list)
	server:refreshBattleUnits(battle)
end

function Script:onAfterMove(server, battle, unit, other, payload)
	if Cloud.cloudImmune(unit, self.spell) then return end
	if E.markVal(unit, Cloud.HIT) ~= nil then return end
	local hexes = E.hexTable(battle)
	local r, center = self:radius(battle, hexes)
	if r < 0 then return end
	if E.unitHexDistance(unit, center) > r then return end
	self:hurt(server, battle, { unit })
end

return Script
