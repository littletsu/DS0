"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[230],{21997:e=>{e.exports=JSON.parse('{"functions":[{"name":"GetDataStore","desc":"Returns the datastore that `key` is being saved to.\\nReturns `nil` if key is ephimeral ([DS0Default.Ephimeral] = true) or is not in defaults.\\n\\n    ","params":[{"name":"key","desc":"","lua_type":"string"}],"returns":[{"desc":"","lua_type":"nil | DataStore | OrderedDataStore"}],"function_type":"static","source":{"line":487,"path":"src/DS0.lua"}},{"name":"SavePlayer","desc":"Saves `Player`\'s data into datastores.\\nThis should only be called after an important change in the player\'s data\\nor periodically only if needed.\\n**This will round any non integers in an [OrderedDataStore] ([DS0Default.Ordered] = true), which will trigger a change event**\\n    ","params":[{"name":"Player","desc":"","lua_type":"Player"}],"returns":[],"function_type":"static","yields":true,"source":{"line":510,"path":"src/DS0.lua"}},{"name":"Init","desc":"Initializes DS0 with defaults for the player data and optionally a version *(see [ServerDS0.DefaultsVersion])*.\\nThis will also automatically get all connected and\\nnew player\'s data, and save a player\'s data once they leave the game.\\n\\nThis should be called before any player is tried to get using [ServerDS0.GetPlayer].\\n**This function should only be called once**\\n\\nA key that is not in the defaults will not be recognized\\nby DS0 and will warn if you try to set it for a player.\\n\\nTo yield the current thread until the server is initialized, use [ServerDS0.YieldUntilInit]\\n\\nExample of initializing player defaults *(see [DS0Default])*:\\n```lua\\nlocal PlayerDefaults = {\\n    -- Defaults to 0, and will be saved in an OrderedDataStore\\n    Wins = DS0.Default(0, true),\\n    -- Defaults to {}\\n    InventoryItems = DS0.Default({}),\\n    -- Defaults to 0 and will not be saved,\\n    -- therefore will reset when the player joins the game again\\n    TimeInGame = DS0.Default(0, false, true)\\n}\\nDS0.Server.Init(PlayerDefaults)\\n```\\n\\n    ","params":[{"name":"defaults","desc":"","lua_type":"DS0Defaults"},{"name":"version","desc":"","lua_type":"number?"}],"returns":[],"function_type":"static","yields":true,"source":{"line":607,"path":"src/DS0.lua"}},{"name":"YieldUntilInit","desc":"Yields the current thread until the server has successfully initialized.\\n\\nBeware when using in a [ModuleScript], as yielding in the wrong places can lead to an infinite yield,\\nso the responsabillity of ensuring whether the server has initialized\\nshould be delegated to whatever is calling the module.\\n\\n    ","params":[],"returns":[],"function_type":"static","yields":true,"source":{"line":651,"path":"src/DS0.lua"}},{"name":"GetPlayer","desc":"Returns the [DS0Player] for `Player`\\n\\nIncrement a player\'s Wins when a proximity prompt is triggered:\\n```lua\\nproximityPrompt.Triggered:Connect(function(player)\\n    local ds0Player = DS0.Server.GetPlayer(player)\\n    ds0Player.Set(\\"Wins\\", function(currentValue)\\n        return currentValue + 1\\n    end)\\nend)\\n```\\n\\n    ","params":[{"name":"Player","desc":"","lua_type":"Player"}],"returns":[{"desc":"","lua_type":"DS0Player"}],"function_type":"static","source":{"line":674,"path":"src/DS0.lua"}},{"name":"OnPlayerLoaded","desc":"Adds an event listener to call `callback` when\\na new player has been successfully initialized\\nand data can be read and written to it.\\n\\n```lua\\nDS0.Server.OnPlayerLoaded(function(player: Player, ds0Player: DS0.DS0Player)\\n    print(`{player.Name} has loaded and has {ds0Player.Get(\\"Wins\\")} wins!`)\\nend)\\n```\\n\\n    ","params":[{"name":"callback","desc":"","lua_type":"DS0PlayerLoadedCallback"}],"returns":[{"desc":"","lua_type":"CallbackRemover"}],"function_type":"static","source":{"line":692,"path":"src/DS0.lua"}},{"name":"ProcessInitialValue","desc":"Sets a `callback` (that returns a first boolean value, `changed`, and a second `value`)\\nto be called before `key` is initially replicated\\nto the client and changes `key` to `value` if `changed` is `true`.\\nIt is important that `changed` is returned `false` if the\\nvalue hasn\'t changed, or `true` if it has, in order for DS0\\nto know whether to save the value or not.\\n\\nThis should ideally be called before [ServerDS0.Init].\\nThe changed value will be saved to the datastores too.\\n\\nThis is useful if processing of a value is needed before it\'s replicated to the client for the first time or initially retrieved.\\n\\nRemoving items from an inventory that are considered deleted (0) to optimize the data:\\n```lua\\n-- Items is an array of Item or 0 (deleted)\\nDS0.Server.ProcessInitialValue(\\"InventoryItems\\", function(items: {[number]: Item|0})\\n    local changed = false\\n    local newItems = {}\\n\\n    -- Filtering through the items, excluding the items that are 0\\n    -- from being added into the new array\\n    for _,item in items do\\n        if item == 0 then\\n            -- We are changing the table by not adding an item\\n            -- that previously was in the table\\n            changed = true\\n            continue\\n        end\\n        table.insert(newItems, item)\\n    end\\n\\n    return changed, newItems\\nend)\\n```\\n\\n    ","params":[{"name":"key","desc":"","lua_type":"string"},{"name":"callback","desc":"","lua_type":"DS0ProcessValueCallback"}],"returns":[{"desc":"","lua_type":"CallbackRemover"}],"function_type":"static","source":{"line":735,"path":"src/DS0.lua"}}],"properties":[{"name":"DefaultsVersion","desc":"A number that is appended to the datastore name. Defaults to `0`\\n    ","lua_type":"number","readonly":true,"source":{"line":175,"path":"src/DS0.lua"}},{"name":"MaxDataStoreRetries","desc":"Retries that will be done to get a datastore for a key if an error occurs. Defaults to `10`\\n    ","lua_type":"number","source":{"line":186,"path":"src/DS0.lua"}},{"name":"MaxGetRetries","desc":"Retries that will be done to get a player\'s key from its datastore if an error occurs. Defaults to `5`\\n    ","lua_type":"number","source":{"line":415,"path":"src/DS0.lua"}},{"name":"MaxSaveRetries","desc":"Retries that will be done to save a player\'s data if an error occurs. Defaults to `5`\\n    ","lua_type":"number","source":{"line":500,"path":"src/DS0.lua"}}],"types":[{"name":"DS0ProcessValueCallback","desc":"Callback that receives the current value and\\nreturns a first boolean value, `changed`, and a second `value`\\n    ","lua_type":"(value: any) -> (boolean, any)","source":{"line":230,"path":"src/DS0.lua"}},{"name":"DS0PlayerLoadedCallback","desc":"Called when a player has been successfully initialized\\nand data can be read and written to it.\\n    ","lua_type":"(Player: Player, DS0Player: DS0Player) -> ()","source":{"line":406,"path":"src/DS0.lua"}}],"name":"ServerDS0","desc":"The server handles the player datastores and automatically replicates\\nany changes to the client.\\n\\nInitialize the player default data *(see [ServerDS0.Init])*:\\n```lua\\nlocal PlayerDefaults = {\\n    -- Defaults to 0, and will be saved in an OrderedDataStore\\n    Wins = DS0.Default(0, true),\\n    -- Defaults to {}\\n    InventoryItems = DS0.Default({}),\\n    -- Defaults to 0 and will not be saved,\\n    -- therefore will reset when the player joins the game again\\n    TimeInGame = DS0.Default(0, false, true)\\n}\\nDS0.Server.Init(PlayerDefaults)\\n```\\n\\nDo something when a player is loaded *(see [ServerDS0.OnPlayerLoaded])*:\\n```lua\\nDS0.Server.OnPlayerLoaded(function(player: Player, ds0Player: DS0.DS0Player)\\n    print(`{player.Name} is loaded and has {ds0Player.Get(\\"Wins\\")} wins!`)\\n    ds0Player.OnKeyChanged(\\"Wins\\", function(newValue)\\n        print(`{player.Name} now has {newValue} wins!`)\\n    end)\\nend)\\n```\\n\\nIncrement a player\'s Wins when a proximity prompt is triggered *(see [ServerDS0.GetPlayer])*:\\n```lua\\nproximityPrompt.Triggered:Connect(function(player)\\n    local ds0Player = DS0.Server.GetPlayer(player)\\n    ds0Player.Set(\\"Wins\\", function(currentValue)\\n        return currentValue + 1\\n    end)\\nend)\\n```","source":{"line":165,"path":"src/DS0.lua"}}')}}]);