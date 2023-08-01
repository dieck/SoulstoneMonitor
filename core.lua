local L = LibStub("AceLocale-3.0"):GetLocale("SoulstoneMonitor", true)

local defaults = {
  char = {
	minimap = {
		hide = false
	}
  }
}

function SoulstoneMonitor:OnInitialize()
	-- Code that you want to run when the addon is first loaded goes here.
	self.db = LibStub("AceDB-3.0"):New("SoulstoneMonitorDB", defaults)

	self:RegisterChatCommand('soulstonemonitor', 'handleChatCommand');
	self:RegisterChatCommand('SoulstoneMonitor', 'handleChatCommand');

	self.minimapbutton = SoulstoneMonitor:CreateMinimapButton()

end

function SoulstoneMonitor:CreateMinimapButton()

	local ssLDB = LibStub("LibDataBroker-1.1"):NewDataObject("SoulstoneMonitor", {
		type = "data source",
		text = tostring(SoulstoneMonitor:tablesize(self.db.char.stones) or 0),
		label = "SoulstoneMonitor",
		icon = "Interface\\Icons\\inv_misc_orb_04" })
	self.ssLDB = ssLDB

	self.db.char.minimap = { hide = false }

	local icon = LibStub("LibDBIcon-1.0")
	icon:Register("SoulstoneMonitor", self.ssLDB, self.db.char.minimap)

	function ssLDB:OnTooltipShow()
		SoulstoneMonitor:Cleanup()
		SoulstoneMonitor:ScanRaid()

		if SoulstoneMonitor.db.char.stones == nil then SoulstoneMonitor.db.char.stones = {} end
		if tempty(SoulstoneMonitor.db.char.stones) then
			self:AddLine("No current Soulstones recorded.")
		else
			for caster,cast in pairs(SoulstoneMonitor.db.char.stones) do
				local remainingMin = (cast["when"] + (15*60)) - GetTime()
				if remainingMin < 60 then
					remainingMin = tostring(floor(remainingMin)) .. "sec"
				else
					remainingMin = tostring(floor(remainingMin/60)) .. "min"
				end
				self:AddLine(cast["target"] .. ", " .. remainingMin .. " left, cast by " .. caster)
			end
		end
	end

	function ssLDB:OnEnter()
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
		GameTooltip:ClearLines()
		ssLDB.OnTooltipShow(GameTooltip)
		GameTooltip:Show()
	end

	function ssLDB:OnLeave()
		GameTooltip:Hide()
	end

	return icon
end

function SoulstoneMonitor:OnEnable()
  -- Called when the addon is enabled
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

  -- start cleanup and search once
  SoulstoneMonitor:Cleanup()
  SoulstoneMonitor:ScanRaid()

  -- and repeat every 60 / 15 sec. Seems long? Yes, maybe, but normally should be ok
  self.timerScan = self:ScheduleRepeatingTimer("ScanRaid", 60)
  self.timerClean = self:ScheduleRepeatingTimer("Cleanup", 15)

  if (not self.db.char.minimap.hide) then
	self.minimapbutton:Show()
  end

end

function SoulstoneMonitor:OnDisable()
    -- Called when the addon is disabled
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:CancelAllTimers()
end

function SoulstoneMonitor:handleChatCommand(cmd)
	self.db.char.minimap.hide = not self.db.char.minimap.hide

	if self.db.char.minimap.hide
	then self.minimapbutton:Hide("SoulstoneMonitor")
	else self.minimapbutton:Show("SoulstoneMonitor")
	end
end

function SoulstoneMonitor:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
	local _, subevent, _, sourceGUID, _, _, _, _, destName = CombatLogGetCurrentEventInfo()
	local spellId

	if subevent == "SPELL_CAST_SUCCESS" then
		spellId = select(12, CombatLogGetCurrentEventInfo())
	end

	-- only care about applying Soulstone
	if spellId == nil then return end
	if spellId ~= 6203 then return end

	local locClass, engClass, locRace, engRace, gender, name, server = GetPlayerInfoByGUID(sourceGUID)

	if SoulstoneMonitor.db.char.stones == nil then SoulstoneMonitor.db.char.stones = {}	end

	-- use GetTime (system uptime of your computer in seconds, with millisecond precision) instead of time() (Epoch)
	SoulstoneMonitor.db.char.stones[name] = { when = GetTime(), target = destName }
	SoulstoneMonitor:Print(name .. " soulstoned " .. destName)
	self.ssLDB.text = tostring(SoulstoneMonitor:tablesize(self.db.char.stones) or 0)
end


function SoulstoneMonitor:Cleanup(debugNoRemove)
	-- remove everything older than 15min
	for caster,cast in pairs(SoulstoneMonitor.db.char.stones) do
		if (cast["when"] + 15*60) < GetTime() then
			if (debugNoRemove) then
				SoulstoneMonitor:Print("DEBUG - Will NOT remove Soulstone entry (max buff duration) for " .. cast["target"])
			else
				SoulstoneMonitor.db.char.stones[caster] = nil
			end
		end
	end

	-- go through chars and see if still active
	for caster,cast in pairs(SoulstoneMonitor.db.char.stones) do

		-- for all chars in a raid or party, or me alone (yes, party members will be checked twice if in raid)
		local units = {"player"}
		for i=1,5 do tinsert(units, "party" .. tostring(i)) end
		for i=1,40 do tinsert(units, "raid" .. tostring(i)) end

		for _,unit in pairs(units) do
			-- did I find my target?
			if UnitName(unit) == cast["target"] then
				-- go through all buffs
				local foundSoulstone = false

				local j = 1
				local name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, j)

				while name ~= nil do
					-- look for Soulstone
					if (spellId == 47883) or (spellId == 27239) or (spellId == 20765) or (spellId == 20764) or (spellId == 20763) or (spellId == 20762) or (spellId == 20707) then
						foundSoulstone = true
					end
					j = j + 1
					name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, j)
				end

				if (not foundSoulstone) then
					if (debugNoRemove) then
						SoulstoneMonitor:Print("DEBUG - Will NOT remove Soulstone entry (buff no longer found) for " .. cast["target"])
					else
						SoulstoneMonitor.db.char.stones[caster] = nil
					end
				end

			end
		end

	end
	self.ssLDB.text = tostring(SoulstoneMonitor:tablesize(self.db.char.stones) or 0)
end

function SoulstoneMonitor:findNextUnknown()
	if SoulstoneMonitor.db.char.stones == nil then SoulstoneMonitor.db.char.stones = {} end
	local i = 1
	while SoulstoneMonitor.db.char.stones["unknown-" .. tostring(i)] ~= nil do i = i + 1 end
	return i
end

function SoulstoneMonitor:ScanRaid()
	-- for all chars in a raid or party, or me alone (yes, party members will be checked twice if in raid - but second time unknown entry will be found)
	local units = {"player"}
	for i=1,5 do tinsert(units, "party" .. tostring(i)) end
	for i=1,40 do tinsert(units, "raid" .. tostring(i)) end

	for _,unit in pairs(units) do

		if (UnitName(unit) ~= nil) then

			-- go through all buffs
			local foundSoulstone = false

			local j = 1
			local name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, j)

			while name ~= nil do
				-- look for Soulstone
				if (spellId == 47883) or (spellId == 27239) or (spellId == 20765) or (spellId == 20764) or (spellId == 20763) or (spellId == 20762) or (spellId == 20707) then

					-- found Soulstone. So let's see if we have a cast noted down for that

					local foundCast = false
					for caster,cast in pairs(SoulstoneMonitor.db.char.stones) do
						if cast["target"] == UnitName(unit) then foundCast = true end
					end

					if (not foundCast) then
						SoulstoneMonitor.db.char.stones["unknown-" .. SoulstoneMonitor:findNextUnknown()] = { when = expirationTime-(15*60), target = UnitName(unit) }
						SoulstoneMonitor:Print("Found new soulstone without recorded cast on " .. UnitName(unit))
					end

				end
				j = j + 1
				name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, j)
			end

		end

	end
	self.ssLDB.text = tostring(SoulstoneMonitor:tablesize(self.db.char.stones) or 0)

end


-- for debug outputs
function tprint (tbl, indent)
	if not indent then indent = 0 end
	local toprint = string.rep(" ", indent) .. "{\r\n"
	indent = indent + 2
	for k, v in pairs(tbl) do
	  toprint = toprint .. string.rep(" ", indent)
	  if (type(k) == "number") then
		toprint = toprint .. "[" .. k .. "] = "
	  elseif (type(k) == "string") then
		toprint = toprint  .. k ..  "= "
	  end
	  if (type(v) == "number") then
		toprint = toprint .. v .. ",\r\n"
	  elseif (type(v) == "string") then
		toprint = toprint .. "\"" .. v .. "\",\r\n"
	  elseif (type(v) == "table") then
		toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
	  else
		toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
	  end
	end
	toprint = toprint .. string.rep(" ", indent-2) .. "}"
	return toprint
end

function SoulstoneMonitor:tablesize(t)
	  local count = 0
	  for _, __ in pairs(t) do
		  count = count + 1
	  end
	  return count
end

function tempty(t)
	  if t == nil then return true end
	  if SoulstoneMonitor:tablesize(t) > 0 then return false end
	  return true
end

function SoulstoneMonitor:Debug(t, lvl)
    if lvl == nil then
	  lvl = "DEBUG"
	end
	if (SoulstoneMonitor.db.profile.debug) then
		if (type(t) == "table") then
			SoulstoneMonitor:Print(lvl .. ": " .. tprint(t))
		else
			SoulstoneMonitor:Print(lvl .. ": " .. t)
		end
	end
end