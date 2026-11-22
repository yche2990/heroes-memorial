local Base = require("spells/spellEffect")
local L = require("spells/h7abLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- "Shapes" of H7 area shots (batch E). Only used on spells pointed to by SPELL_LIKE_ATTACK (creatures never really cast these spells):
--- for area shots the engine uses this spell to work out the affected stacks (BattleSpellMechanics::getAffectedStacks -> transformTarget),
--- each affected stack takes one normal shot's damage (as the H3 Magog), highlighted by adjustAffectedHexes when choosing.
---   mode = "area"  all stacks on the target hex and the ring around it (radius, default 1; H7's 3x3), friend or foe, the shooter excluded
---                  (Mana Nova, Splash, Scatter Shot)
---   mode = "line"  the straight line from the shooter through the target hex to the edge of the battlefield, all enemies on it (Leaf Blade)
--- Magic immunity is ignored (this is a normal attack, not a spell); the engine itself skips invincible stacks.

local function cube(hex)
	local y = hex:getY()
	local q = hex:getX() + math.floor(y / 2) - y
	return q, y, -q - y
end

local function cubeRound(fq, fr, fs)
	local q, r, s = math.floor(fq + 0.5), math.floor(fr + 0.5), math.floor(fs + 0.5)
	local dq, dr, ds = math.abs(q - fq), math.abs(r - fr), math.abs(s - fs)
	if dq > dr and dq > ds then q = -r - s elseif dr > ds then r = -q - s end
	return q, r
end

local function toIndex(q, r)
	local y = r
	local x = q + y - math.floor(y / 2)
	if y < 0 or y > 10 or x < 1 or x > 15 then return nil end
	return x + y * 17
end

--- Line from the shooter's hex -> aim (start excluded), extended to the battlefield edge
function Script.lineHexes(battle, from, aim)
	local table_ = L.hexTable(battle)
	local n = L.hexDistance(from, aim)
	local out = {}
	if n == 0 then return out end
	local aq, ar, as = cube(from)
	local bq, br, bs = cube(aim)
	local seen = {}
	for t = 1, 40 do
		local k = t / n
		-- Tiny offset, to avoid wavering when exactly on the border of two hexes
		local q, r = cubeRound(aq + (bq - aq) * k + 1e-6, ar + (br - ar) * k + 2e-6, as + (bs - as) * k - 3e-6)
		local idx = toIndex(q, r)
		if idx == nil then break end
		local h = table_[idx]
		if h == nil then break end
		if not seen[idx] then
			seen[idx] = true
			out[#out + 1] = h
		end
	end
	return out
end

function Script:areaHexes(battle, center)
	local out = {}
	local r = self.radius or 1
	for _, h in pairs(L.hexTable(battle)) do
		if L.hexDistance(h, center) <= r then out[#out + 1] = h end
	end
	return out
end

local function aimHex(aimPoint, spellTarget)
	local d = (spellTarget and spellTarget[1]) or (aimPoint and aimPoint[1])
	if d == nil then return nil end
	if d.hex ~= nil and d.hex:isValid() then return d.hex end
	if d.unit ~= nil then return d.unit:getPosition() end
	return nil
end

function Script:hexesFor(mechanics, hex)
	local battle = mechanics:getBattle()
	if self.mode == "line" then
		local caster = mechanics:getUnitCaster()
		if caster == nil then return { hex } end
		return Script.lineHexes(battle, caster:getPosition(), hex)
	end
	return self:areaHexes(battle, hex)
end

function Script:applicableTarget(mechanics, problem, target)
	return aimHex(target, target) ~= nil
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local hex = aimHex(aimPoint, spellTarget)
	if hex == nil then return {} end
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local seen, out = {}, {}
	for _, h in ipairs(self:hexesFor(mechanics, hex)) do
		local u = battle:getUnitByPos(h, true)
		if u ~= nil and not seen[u:unitID()] and u:isAlive() and not u:isGhost() then
			seen[u:unitID()] = true
			local ok = true
			if caster ~= nil then
				if u:unitID() == caster:unitID() then ok = false end
				if self.mode == "line" and not L.isEnemyOf(caster, u) then ok = false end
			end
			if ok then out[#out + 1] = { unit = u, hex = u:getPosition() } end
		end
	end
	return out
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local hex = aimHex(spellTarget, spellTarget)
	if hex ~= nil then
		for _, h in ipairs(self:hexesFor(mechanics, hex)) do hexes:insert(h) end
	end
	return hexes
end

function Script:apply(mechanics, server, target)
	-- Only used to work out the area, never really cast
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
