--!strict
--[[
	DataService.luau
	Saves and loads player profiles with DataStoreService.

	- Load: GetAsync with retries. A new player (no save) gets a fresh profile. If loading FAILS, the player
	  still gets a fresh profile to play with, but that session is never saved, so a bad load can't wipe
	  their real save.
	- Save: UpdateAsync with the serialized profile (see ProfileSerializer).
	- Autosave every GameConfig.Save.AutosaveSeconds, save on leave, and save everyone on server shutdown.

	Studio: needs a published place and, set by the experience owner,
	File > Experience Settings > Security > "Enable Studio Access to API Services".
	Without it, saving is switched off with one warning and the game still runs (nothing is saved).

	Known limit: no session locking. If a player rejoins another server before this one finishes saving,
	the new server can read the older save. Fine for now; revisit before launch.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ProfileSerializer = require(Shared:WaitForChild("ProfileSerializer"))
local ProgressionLogic = require(Shared:WaitForChild("ProgressionLogic"))

local DataService = {}

local cfg = GameConfig.Save
local store: DataStore? = nil
local storeDisabled = false
local warnedDisabled = false

-- Players whose save was read successfully this session. Only these are ever written back.
local canSave: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}
-- Saves currently running (leave-saves included), so shutdown can wait for all of them
local inFlight = 0

local function warnDisabled(reason: string)
	if not warnedDisabled then
		warnedDisabled = true
		local fix = if string.find(reason, "Studio", 1, true) or string.find(reason, "publish", 1, true)
			then "\n  FIX (experience owner): File > Experience Settings > Security > Enable Studio Access to API Services."
			else ""
		warn(`[DataService] Saving is OFF this session: {reason}{fix}`)
	end
end

local function getStore(): DataStore?
	if store or storeDisabled then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(cfg.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeDisabled = true
		warnDisabled(tostring(result))
	end
	return store
end

-- Errors that retrying can't fix (Studio without API access, unpublished place)
local function isPermanentError(err: string): boolean
	return string.find(err, "403", 1, true) ~= nil
		or string.find(err, "Studio", 1, true) ~= nil
		or string.find(err, "publish", 1, true) ~= nil
end

local function keyFor(player: Player): string
	return cfg.KeyPrefix .. tostring(player.UserId)
end

-- Returns (profile, loadedOk). loadedOk = false means "play, but don't save this session".
function DataService.Load(player: Player): (ProgressionLogic.PlayerProfile, boolean)
	local ds = getStore()
	if not ds then
		canSave[player] = nil
		return ProgressionLogic.CreateInitialProfile(), false
	end

	local key = keyFor(player)
	for attempt = 1, cfg.LoadRetries do
		local ok, result = pcall(function()
			return ds:GetAsync(key)
		end)
		if ok then
			canSave[player] = true
			return ProfileSerializer.Deserialize(result), true
		end
		local err = tostring(result)
		if isPermanentError(err) then
			storeDisabled = true
			store = nil
			warnDisabled(err)
			break
		end
		warn(`[DataService] Load attempt {attempt} failed for {player.Name}: {err}`)
		if attempt < cfg.LoadRetries then
			task.wait(cfg.RetryDelaySeconds)
		end
	end

	canSave[player] = nil
	return ProgressionLogic.CreateInitialProfile(), false
end

function DataService.Save(player: Player, profile: ProgressionLogic.PlayerProfile): boolean
	if not canSave[player] then
		return false
	end
	local ds = getStore()
	if not ds then
		return false
	end
	while saving[player] do
		task.wait(0.05)
	end
	if not canSave[player] then
		return false
	end
	saving[player] = true
	profile.LastSeen = os.time()
	local data = ProfileSerializer.Serialize(profile)
	inFlight += 1
	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	inFlight -= 1
	saving[player] = nil
	if not ok then
		warn(`[DataService] Save failed for {player.Name}: {tostring(err)}`)
	end
	return ok
end

function DataService.CanSave(player: Player): boolean
	return canSave[player] == true
end

-- Final save when a player leaves. `profile` is captured by the caller before it drops the profile.
function DataService.SaveAndRelease(player: Player, profile: ProgressionLogic.PlayerProfile?)
	if profile then
		DataService.Save(player, profile)
	end
	canSave[player] = nil
end

-- Starts autosave + shutdown saving. `getProfiles` returns every online player's live profile.
function DataService.Start(getProfiles: () -> { [Player]: ProgressionLogic.PlayerProfile })
	task.spawn(function()
		while true do
			task.wait(cfg.AutosaveSeconds)
			for player, profile in getProfiles() do
				task.spawn(DataService.Save, player, profile)
			end
		end
	end)

	-- Shutdown: save everyone still online, then wait for every running save (including the ones
	-- PlayerRemoving started) before letting the server close. Roblox allows ~30s here.
	game:BindToClose(function()
		for player, profile in getProfiles() do
			task.spawn(DataService.SaveAndRelease, player, profile)
		end
		task.wait() -- let the spawned saves start (and count themselves in inFlight)
		local waited = 0
		while inFlight > 0 and waited < 25 do
			waited += task.wait(0.1)
		end
	end)
end

return DataService
