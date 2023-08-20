local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Remotes)
local Callbacks = require(ReplicatedStorage.Shared.Module.Callbacks)
local Connections = require(ReplicatedStorage.Shared.Module.Connections)
local Promise = require(ReplicatedStorage.Packages.Promise)

--[=[
    DS0 is a datastore wrapper for saving and reading players data that replicates changes to the client.

    Includes [DS0.Server] for working with players data and [DS0.Client] for working with the local player's data
    @class DS0
]=]
local DS0 = {}

--[=[
    A function that when called will stop the callback from being called again
    @type CallbackRemover () -> ()
    @within DS0
]=]

--[=[
    Returns the key of the player that will be saved on the datastores. Only useful if you're accessing the raw datastores
]=]
function DS0.GetPlayerKey(Player: Player)
    return tostring(Player.UserId)
end

--[=[
    Makes a [DS0Default] using the arguments provided

    @param value any -- The default value of the key
    @param ordered boolean|nil -- Whether the value will be saved in an [OrderedDataStore]. Defaults to false, will be false if value is not a number
    @param ephimeral boolean|nil -- Whether the value will be saved (false) or will disappear (true) when the player leaves the game. Defaults to false

    @return DS0Default
    @within DS0
]=]
function DS0.Default(value: any, ordered: boolean | nil, ephimeral: boolean | nil)
    local IsOrdered: boolean = if type(value) ~= "number" then (false) else (ordered or false)
    local IsEphimeral: boolean = if ephimeral ~= nil then ephimeral else false
    return {
        Value = value,
        Ordered = IsOrdered,
        Ephimeral = IsEphimeral
    }
end

--[=[
    A default for a key. Making this interface manually can be verbose so using [DS0.Default] is recommended.
    @interface DS0Default
    @within DS0
    .Value any -- The default value of the key
    .Ordered boolean -- Whether the value will be saved in an [OrderedDataStore]
    .Ephimeral boolean -- Whether the value will be saved (false) or will reset (true) when the player leaves the game
]=]
export type DS0Default = typeof(DS0.Default(0))
--[=[
    A dictionary of a default for each key in a player's data. A player's data will contain each key in here.

    *See [ServerDS0.Init]*

    @type DS0Defaults {[string]: DS0Default}
    @within DS0
]=]
export type DS0Defaults = {[string]: DS0Default}

--[=[
    A dictionary of the values that are contained in the player
    @type DS0SavedPlayer {[string]: any}
    @within DS0
]=]
export type DS0SavedPlayer = {[string]: any}
--[=[
    A dictionary mapping a player to its data
    @type DS0SavedPlayers {[Player]: DS0SavedPlayer}
    @private
    @within DS0
]=]
type DS0SavedPlayers = {[Player]: DS0SavedPlayer}
--[=[
    Callback that receives a new value that has changed
    @type DS0KeyChangedCallback (newValue: any) -> ()
    @within DS0
]=]
type DS0KeyChangedCallback = (newValue: any) -> ()
--[=[
    Callback that receives the current value of the key and returns a new value for the key
    @type DS0SetCallback (currentValue: any) -> any
    @within DS0
]=]
type DS0SetCallback = (currentValue: any) -> any
--[=[
    A dictionary for setting multiple keys in one function call, value is a Set method argument
    @type DS0SetTable {[string]: any | DS0SetCallback}
    @within DS0
]=]
type DS0SetTable = {[string]: any | DS0SetCallback}

--[=[
    The name that will be used for getting the datastores, is `nil` on client.
    @prop DataStoreName string | nil
    @server
    @readonly
    @within DS0
]=]
DS0.DataStoreName = nil

-- from https://gist.github.com/tylerneylon/81333721109155b2d244
function copy(obj, seen)
    -- Handle non-tables and previously-seen tables.
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end

    -- New table; mark it as seen and copy recursively.
    local s = seen or {}
    local res = {}
    s[obj] = res
    for k, v in pairs(obj) do res[copy(k, s)] = copy(v, s) end
    return setmetatable(res, getmetatable(obj))
end

--[=[
    The server handles the player datastores and automatically replicates
    any changes to the client.

    Initialize the player default data *(see [ServerDS0.Init])*:
    ```lua
    local PlayerDefaults = {
        -- Defaults to 0, and will be saved in an OrderedDataStore
        Wins = DS0.Default(0, true),
        -- Defaults to {}
        InventoryItems = DS0.Default({}),
        -- Defaults to 0 and will not be saved,
        -- therefore will reset when the player joins the game again
        TimeInGame = DS0.Default(0, false, true)
    }
    DS0.Server.Init(PlayerDefaults)
    ```

    Do something when a player is loaded *(see [ServerDS0.OnPlayerLoaded])*:
    ```lua
    DS0.Server.OnPlayerLoaded(function(player: Player, ds0Player: DS0.DS0Player)
        print(`{player.Name} is loaded and has {ds0Player.Get("Wins")} wins!`)
        ds0Player.OnKeyChanged("Wins", function(newValue)
            print(`{player.Name} now has {newValue} wins!`)
        end)
    end)
    ```

    Increment a player's Wins when a proximity prompt is triggered *(see [ServerDS0.GetPlayer])*:
    ```lua
    proximityPrompt.Triggered:Connect(function(player)
        local ds0Player = DS0.Server.GetPlayer(player)
        ds0Player.Set("Wins", function(currentValue)
            return currentValue + 1
        end)
    end)
    ```

    @class ServerDS0
]=]
local ServerDS0 = function()
    local module = {}

    local PlayerDefaults: DS0Defaults = {}
    --[=[
        A number that is appended to the datastore name. Defaults to `0`
        @prop DefaultsVersion number
        @readonly
        @within ServerDS0
    ]=]
    module.DefaultsVersion = 0

    local DataStoreService = game:GetService("DataStoreService")
    local EphimeralDataStore = 0
    type PlayersDataStore = {[string]: DataStore|OrderedDataStore}

    --[=[
        Retries that will be done to get a datastore for a key if an error occurs. Defaults to `10`
        @prop MaxDataStoreRetries number
        @within ServerDS0
    ]=]
    module.MaxDataStoreRetries = 10

    local function GetDataStores()
        local PlayersDataStore: PlayersDataStore = {}
        local promises = {}
        for DataStoreKey,Default in PlayerDefaults do
            local promise = Promise.new(function(resolve)
                if Default.Ephimeral then
                    PlayersDataStore[DataStoreKey] = EphimeralDataStore
                    return resolve()
                end
                local fun = if Default.Ordered then DataStoreService.GetOrderedDataStore else DataStoreService.GetDataStore
                local tries = 0
                local function setDataStore()
                    tries += 1
                    Promise.try(function()
                        PlayersDataStore[DataStoreKey] = fun(DataStoreService, DS0.DataStoreName, DataStoreKey)
                    end):andThen(resolve):catch(function(err)
                        if tries >= module.MaxDataStoreRetries then
                            warn(`DS0: Could not get DataStore for {DataStoreKey} after {module.MaxDataStoreRetries} retries! {tostring(err)}`)
                            return resolve()
                        end
                        warn(`DS0: Could not get DataStore for {DataStoreKey}, retrying ({tries}/{module.MaxDataStoreRetries})! {tostring(err)}`)
                        return setDataStore()
                    end)
                end
                setDataStore()
            end)
            table.insert(promises, promise)
        end
        Promise.all(promises):await()
        return PlayersDataStore
    end

    local PlayersDataStore: PlayersDataStore = {}
    local SavedPlayers: DS0SavedPlayers = {}
    local ChangedPlayers: DS0SavedPlayers = {}
    local PlayerLoadedCallbacks: {DS0PlayerLoadedCallback} = {}
    --[=[
        Callback that receives the current value and
        returns a first boolean value, `changed`, and a second `value`
        @type DS0ProcessValueCallback (value: any) -> (boolean, any)
        @within ServerDS0
    ]=]
    export type DS0ProcessValueCallback = (value: any) -> (boolean, any)
    local ProcessValueCallbacks: {[string]: DS0ProcessValueCallback} = {}

    local function GetPlayer(Player: Player)
        --[=[
            A player that can be written to and read from.
            Use [ServerDS0.GetPlayer] to get a [DS0Player] from a [Player] or [ServerDS0.OnPlayerLoaded] to listen to when a player has been initialized.
            @server
            @class DS0Player
        ]=]
        local player = {}
        local keyCallbacks: {[string]: {DS0KeyChangedCallback}} = {}
        local DS0Remotes = Remotes.Server:GetNamespace("DS0")
        local PlayerChanged = DS0Remotes:Get("PlayerChanged")
        local Connected = true
        local Loaded = false

        --[=[
            Returns all the player data

            @return DS0SavedPlayer
            @within DS0Player
        ]=]
        function player.Values()
            return SavedPlayers[Player]
        end

        --[=[
            Returns the value of a key

            ```lua
            print(`Player has {ds0Player.Get("Wins")} wins!`)
            ```

            Equivalent to:
            ```lua
            ds0Player.Values()[key]
            ```

            @return any
            @within DS0Player
        ]=]
        function player.Get(key: string)
            return SavedPlayers[Player][key]
        end

        --[=[
            Adds an event listener to call `callback` when `key` has changed. This listener is removed when the player leaves the game

            ```lua
            ds0Player.OnKeyChanged("Wins", function(newValue)
                print(`Wins is now {newValue}!`)
            end)
            ```

            @return CallbackRemover
            @within DS0Player
        ]=]
        function player.OnKeyChanged(key: string, callback: DS0KeyChangedCallback)
            if keyCallbacks[key] == nil then
                keyCallbacks[key] = {}
            end
            return Callbacks.insertCallback(keyCallbacks[key], callback)
        end

        --[=[
            Sets `key` to `value` and replicates the change to the client.
            A change won't be triggered if the value is not a table and is the same as the previous one.
            For tables changes won't be compared to the previous value.

            If a function is provided as `value`,
            it will be called with the current
            value of `key` as the first argument,
            and `key` will be set to the return value.

            If a table is provided as the first argument,
            the second argument will be ignored and
            [DS0Player.Set] will be called for every element 
            in the table with the key as `key` and the value as `value`.

            Simple set
            ```lua
            ds0Player.Set("Wins", 5)
            ```

            Set using function
            ```lua
            ds0Player.Set("Wins", function(currentValue)
                -- Increment the current value by 1
                return currentValue + 1
            end)
            ```

            Set using table
            ```lua
            ds0Player.Set({
                Wins = function(currentValue)
                    -- Increment the current value by 1
                    return currentValue + 1
                end,
                InventoryItems = {"Potion"}
            })
            ```

            @yields
            @within DS0Player
        ]=]
        function player.Set(key: string | DS0SetTable, value: any | DS0SetCallback)
            if type(key) == "table" then
                for DataStoreKey, PValue in key :: DS0SetTable do
                    player.Set(DataStoreKey, PValue)
                end
                return
            end
            if PlayerDefaults[key] == nil then
                warn(`DS0: {key} set but it is not in defaults! It will not be set`)
                return
            end
            local newValue =
                if type(value) == "function" then value(player.Get(key))
                else value
            if typeof(newValue) ~= "table" and newValue == player.Get(key) then return end
            SavedPlayers[Player][key] = newValue
            ChangedPlayers[Player][key] = newValue
            PlayerChanged:SendToPlayer(Player, key, newValue)
            if keyCallbacks[key] ~= nil then
                Callbacks.callCallbacks(keyCallbacks[key], newValue)
            end
        end

        --[=[
            Returns `true` if the player is still in the game or hasn't been disconnected through [DS0Player.Disconnect].
            @return boolean
            @within DS0Player
        ]=]
        function player.IsConnected()
            return Connected
        end

        --[=[
            Sets [DS0Player.IsConnected] to false. **This function is automatically called when the player leaves the game**
            @return boolean
            @within DS0Player
        ]=]
        function player.Disconnect()
            Connected = false
        end

        --[=[
            Sets the player loaded to true
            @private
            @within DS0Player
        ]=]
        function player._setloaded()
            Loaded = true
        end

        --[=[
            Returns `true` if the player has been successfully initialized.
            @return boolean
            @within DS0Player
        ]=]
        function player.IsLoaded()
            return Loaded
        end

        return player
    end

    export type DS0Player = typeof(GetPlayer(nil))
    --[=[
        Called when a player has been successfully initialized
        and data can be read and written to it.
        @type DS0PlayerLoadedCallback (Player: Player, DS0Player: DS0Player) -> ()
        @within ServerDS0
    ]=]
    export type DS0PlayerLoadedCallback = (Player: Player, DS0Player: DS0Player, DS0PlayerValues: DS0SavedPlayer) -> ()
    local DS0Players: {[Player]: DS0Player} = {}
    local PlayerEvents: {[Player]: Connections.Connections} = {}

    --[=[
        Retries that will be done to get a player's key from its datastore if an error occurs. Defaults to `5`
        @prop MaxGetRetries number
        @within ServerDS0
    ]=]
    module.MaxGetRetries = 5

    local function InitPlayer(Player: Player)
        local start = tick()
        local playerKey = DS0.GetPlayerKey(Player)
        SavedPlayers[Player] = {}
        ChangedPlayers[Player] = {}
        local promises = {}
        for DataStoreKey,dataStore in pairs(PlayersDataStore) do
            local storePromise = Promise.new(function(resolve)
                local defaults = PlayerDefaults[DataStoreKey]
                if defaults.Ephimeral then
                    SavedPlayers[Player][DataStoreKey] = defaults.Value
                    return resolve()
                end
                local function getDataStoreValue()
                    return Promise.new(function(resolve, reject)
                        local tries = 0
                        local function try()
                            tries += 1
                            Promise.try(function()
                                return dataStore:GetAsync(playerKey)
                            end):andThen(resolve):catch(function(err)
                                if tries >= module.MaxGetRetries then
                                    warn(`DS0: Could not get {Player.Name} data for {DataStoreKey} after {module.MaxGetRetries} retries! {tostring(err)}`)
                                    return reject(err)
                                end
                                warn(`DS0: Could not get {Player.Name} data for {DataStoreKey}, retrying ({tries}/{module.MaxGetRetries})! {tostring(err)}`)
                                try()
                            end)
                        end
                        try()
                    end)
                end
                local success, datastoreValue = getDataStoreValue():await()
                if not success then
                    return resolve()
                end
                local value = datastoreValue or copy(defaults.Value)
                local changed = false
                if ProcessValueCallbacks[DataStoreKey] ~= nil then
                    changed, value = ProcessValueCallbacks[DataStoreKey](value)
                end
                SavedPlayers[Player][DataStoreKey] = value
                if not datastoreValue or changed then
                    ChangedPlayers[Player][DataStoreKey] = SavedPlayers[Player][DataStoreKey]
                end
                resolve()
            end)
            table.insert(promises, storePromise)
        end
        Promise.all(promises):await()

        local playerEvent = Connections.new()

        local ds0Player = GetPlayer(Player)

        PlayerEvents[Player] = playerEvent
        DS0Players[Player] = ds0Player

        Callbacks.callCallbacks(PlayerLoadedCallbacks, Player, ds0Player, SavedPlayers[Player]):await()
        ds0Player._setloaded()
        print(`DS0: Player {Player.Name} init in {tick() - start}s`)
    end

    --[=[
        Returns the datastore that `key` is being saved to.
        Returns `nil` if key is ephimeral ([DS0Default.Ephimeral] = true) or is not in defaults.

        @return nil | DataStore | OrderedDataStore
        @within ServerDS0
    ]=]
    function module.GetDataStore(key: string): nil | DataStore | OrderedDataStore
        local datastore = PlayersDataStore[key]
        if datastore == EphimeralDataStore then
            return nil
        end
        return datastore
    end

    --[=[
        Retries that will be done to save a player's data if an error occurs. Defaults to `5`
        @prop MaxSaveRetries number
        @within ServerDS0
    ]=]
    module.MaxSaveRetries = 5

    --[=[
        Saves `Player`'s data into datastores.
        This should only be called after an important change in the player's data
        or periodically only if needed.
        **This will round any non integers in an [OrderedDataStore] ([DS0Default.Ordered] = true), which will trigger a change event**
        @yields
        @within ServerDS0
    ]=]
    function module.SavePlayer(Player: Player)
        local playerKey = DS0.GetPlayerKey(Player)
        local promises = {}
        for DataStoreKey,value in pairs(ChangedPlayers[Player]) do
            local function saveHandler(resolve)
                local tries = 0
                local defaults = PlayerDefaults[DataStoreKey]
                if defaults.Ephimeral then return resolve() end
                local dataStore = PlayersDataStore[DataStoreKey]
                if defaults.Ordered and type(value) == "number" then
                    local ds0Player = DS0Players[Player]
                    local newValue = math.floor(value)
                    ds0Player.Set(DataStoreKey, newValue)
                    value = newValue
                end
                local function saveToDataStore()
                    tries += 1
                    Promise.try(function()
                        return dataStore:SetAsync(playerKey, value)
                    end):andThen(resolve):catch(function(err)
                        if tries >= module.MaxSaveRetries then
                            warn(`DS0: Could not save {Player.Name} data for {DataStoreKey} after {module.MaxSaveRetries} retries! {tostring(err)}`)
                            return resolve()
                        end
                        warn(`DS0: Could not save {Player.Name} data for {DataStoreKey}, retrying ({tries}/{module.MaxSaveRetries})! {tostring(err)}`)
                        return saveToDataStore()
                    end)
                end
                saveToDataStore()
            end
            local savePromise = Promise.new(saveHandler)
            table.insert(promises, savePromise)
        end
        Promise.all(promises):await()
        ChangedPlayers[Player] = {}
    end

    local function RemovePlayer(Player: Player)
        PlayerEvents[Player].DisconnectAll()
        PlayerEvents[Player] = nil
        module.SavePlayer(Player)
        DS0Players[Player].Disconnect()
        DS0Players[Player] = nil
    end

    local function SaveAllPlayers(method: (Player: Player) -> any)
        local threads = 0
        local mainThread = coroutine.running()
        local save = coroutine.wrap(function(Player: Player)
            method(Player)
            threads -= 1
            if threads == 0 then
                coroutine.resume(mainThread)
            end
        end)
        for _,Player in pairs(Players:GetPlayers()) do
            threads += 1
            save(Player)
        end
        if threads > 0 then
            coroutine.yield()
        end
    end

    local WaitingInit: {thread} = {}
    local Init = false

    --[=[
        Initializes DS0 with defaults for the player data and optionally a version *(see [ServerDS0.DefaultsVersion])*.
        This will also automatically get all connected and
        new player's data, and save a player's data once they leave the game.

        This should be called before any player is tried to get using [ServerDS0.GetPlayer].
        **This function should only be called once**

        A key that is not in the defaults will not be recognized
        by DS0 and will warn if you try to set it for a player.

        To yield the current thread until the server is initialized, use [ServerDS0.YieldUntilInit]

        Example of initializing player defaults *(see [DS0Default])*:
        ```lua
        local PlayerDefaults = {
            -- Defaults to 0, and will be saved in an OrderedDataStore
            Wins = DS0.Default(0, true),
            -- Defaults to {}
            InventoryItems = DS0.Default({}),
            -- Defaults to 0 and will not be saved,
            -- therefore will reset when the player joins the game again
            TimeInGame = DS0.Default(0, false, true)
        }
        DS0.Server.Init(PlayerDefaults)
        ```

        @yields
        @within ServerDS0
    ]=]
    function module.Init(defaults: DS0Defaults, version: number?)
        PlayerDefaults = defaults
        if version then
            module.DefaultsVersion = version
        end
        DS0.DataStoreName = "PlayersDataStore" .. module.DefaultsVersion
        PlayersDataStore = GetDataStores()
        for _,Player in pairs(Players:GetPlayers()) do
            InitPlayer(Player)
        end
        Players.PlayerAdded:Connect(InitPlayer)
        Players.PlayerRemoving:Connect(RemovePlayer)
        game:BindToClose(function()
            local saveInStudio = ReplicatedStorage:FindFirstChild("SaveDataInStudio")
            if RunService:IsStudio() and (saveInStudio == nil or saveInStudio.Value == false) then
                print("Player DataStores are not guaranteed to save because SaveDataInStudio is false!")
                return
            end
            SaveAllPlayers(RemovePlayer)
        end)
        local DS0Remotes = Remotes.Server:GetNamespace("DS0")
        local GetLocalPlayer = DS0Remotes:Get("GetLocalPlayer")
        GetLocalPlayer:SetCallback(function(player: Player)
            print("DS0: GetLocalPlayer Remote " .. player.Name)
            local ds0plr: DS0Player = module.GetPlayer(player)
            if ds0plr == nil or not ds0plr.IsLoaded() then return false end
            return ds0plr.Values()
        end)
        Init = true
        for _,thread in pairs(WaitingInit) do
            coroutine.resume(thread)
        end
    end

    --[=[
        Yields the current thread until the server has successfully initialized.

        Beware when using in a [ModuleScript], as yielding in the wrong places can lead to an infinite yield,
        so the responsabillity of ensuring whether the server has initialized
        should be delegated to whatever is calling the module.

        @yields
        @within ServerDS0
    ]=]
    function module.YieldUntilInit()
        if not Init then
            table.insert(WaitingInit, coroutine.running())
            coroutine.yield()
        end
    end

    --[=[
        Returns the [DS0Player] for `Player`

        Increment a player's Wins when a proximity prompt is triggered:
        ```lua
        proximityPrompt.Triggered:Connect(function(player)
            local ds0Player = DS0.Server.GetPlayer(player)
            ds0Player.Set("Wins", function(currentValue)
                return currentValue + 1
            end)
        end)
        ```

        @return DS0Player
        @within ServerDS0
    ]=]
    function module.GetPlayer(Player: Player)
        return DS0Players[Player]
    end

    --[=[
        Adds an event listener to call `callback` when
        a new player has been successfully initialized
        and data can be read and written to it.

        ```lua
        DS0.Server.OnPlayerLoaded(function(player: Player, ds0Player: DS0.DS0Player)
            print(`{player.Name} has loaded and has {ds0Player.Get("Wins")} wins!`)
        end)
        ```

        @return CallbackRemover
        @within ServerDS0
    ]=]
    function module.OnPlayerLoaded(callback: DS0PlayerLoadedCallback)
        return Callbacks.insertCallback(PlayerLoadedCallbacks, callback)
    end

    --[=[
        Sets a `callback` (that returns a first boolean value, `changed`, and a second `value`)
        to be called before `key` is initially replicated
        to the client and changes `key` to `value` if `changed` is `true`.
        It is important that `changed` is returned `false` if the
        value hasn't changed, or `true` if it has, in order for DS0
        to know whether to save the value or not.

        This should ideally be called before [ServerDS0.Init].
        The changed value will be saved to the datastores too.

        This is useful if processing of a value is needed before it's replicated to the client for the first time or initially retrieved.

        Removing items from an inventory that are considered deleted (0) to optimize the data:
        ```lua
        -- Items is an array of Item or 0 (deleted)
        DS0.Server.ProcessInitialValue("InventoryItems", function(items: {[number]: Item|0})
            local changed = false
            local newItems = {}

            -- Filtering through the items, excluding the items that are 0
            -- from being added into the new array
            for _,item in items do
                if item == 0 then
                    -- We are changing the table by not adding an item
                    -- that previously was in the table
                    changed = true
                    continue
                end
                table.insert(newItems, item)
            end

            return changed, newItems
        end)
        ```

        @return CallbackRemover
        @within ServerDS0
    ]=]
    function module.ProcessInitialValue(key: string, callback: DS0ProcessValueCallback)
        return Callbacks.setCallback(ProcessValueCallbacks, key, callback)
    end

    return module
end

--[=[
    The client will request the player's saved data to the server initially,
    and after that every change in the player's data will be replicated to the client.

    The client can be generally thought of as a [DS0Player] but without the Set method.

    Reacting to changes on a key *(see [ClientDS0.OnKeyChanged])*:
    ```lua
    local currentWins = DS0.Client.Get("Wins")
    print(`Current wins is {currentWins}!`)
    DS0.Client.OnKeyChanged("Wins", function(newValue)
        currentWins = newValue
        print(`Wins is now {currentWins}!`)
        -- do something else with currentWins...
    end)
    ```

    @class ClientDS0
]=]
local ClientDS0 = function()
    local module = {}
    local keyCallbacks: {[string]: {DS0KeyChangedCallback}} = {}
    local DS0Remotes = Remotes.Client:GetNamespace("DS0")
    local Player: DS0SavedPlayer = false
    while Player == false do
        Player = DS0Remotes:Get("GetLocalPlayer"):CallServer()
    end

    local PlayerChanged = DS0Remotes:Get("PlayerChanged")

    PlayerChanged:Connect(function(ChangedKey: string, ChangedValue: any)
        print(ChangedKey, ChangedValue)
        if Player[ChangedKey] == ChangedValue then return end
        Player[ChangedKey] = ChangedValue
        local callbacks = keyCallbacks[ChangedKey]
        if callbacks ~= nil then
            Callbacks.callCallbacks(callbacks, ChangedValue)
        end
    end)

    --[=[
        Returns all the player data

        @return DS0SavedPlayer
        @within ClientDS0
    ]=]
    function module.Values()
        return Player
    end

    --[=[
        Returns the value of a key

        ```lua
        print(`Client has {DS0.Client.Get("Wins")} wins!`)
        ```

        Equivalent to:
        ```lua
        DS0.Client.Values()[key]
        ```

        @return any
        @within ClientDS0
    ]=]
    function module.Get(key: string)
        return Player[key]
    end

    --[=[
        Adds an event listener to call `callback` when `key` has changed. This listener is removed when the player leaves the game

        ```lua
        DS0.Client.OnKeyChanged("Wins", function(newValue)
            print(`Wins is now {newValue}!`)
        end)
        ```

        @return CallbackRemover
        @within ClientDS0
    ]=]
    function module.OnKeyChanged(key: string, callback: DS0KeyChangedCallback)
        if keyCallbacks[key] == nil then
            keyCallbacks[key] = {}
        end
        return Callbacks.insertCallback(keyCallbacks[key], callback)
    end

    return module
end

--[=[
    Client functions for DS0, is `nil` on server
    @prop Client ClientDS0 | nil
    @client
    @within DS0
]=]
DS0.Client = if RunService:IsClient() then ClientDS0() else nil
--[=[
    Server functions for DS0, is `nil` on client
    @prop Server ServerDS0 | nil
    @server
    @within DS0
]=]
DS0.Server = if RunService:IsServer() then ServerDS0() else nil

return DS0