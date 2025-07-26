--[[
This file is only relative to part 1 of the tutorial. In later parts, it is broken into multiple module scripts for improved readability.
I.e; ClientService, Client (modulescript inherited to ClientService), and Data (modulescript inherited to Client)
]]

-- TypeDef
export type DataValues = {
	-- Members
	level: number,
	xp: number
};

export type DataObject = {
	-- Members
	userId: number,
	values: DataValues,
	
	-- Methods
	Save: () -> nil,
};

export type Client = {
	-- Members
	client: Player, 
	data: Data,
	
	-- Methods
	GetCharacter: () -> Model,
};

-- Constants
local DataStoreService = game:GetService("DataStoreService");
local DataStoreKey = "SaveData__Version0.0.1";
local DataStore = DataStoreService:GetDataStore(DataStoreKey);

local Players = game:GetService("Players");

-- Player Data Table
local Active = {};

-- Data Object Construction
local DataObject;
DataObject = {
	empty = function(): DataValues
		return {
			level = 0,
			xp = 0
		};
	end,
	new = function(userId: number): DataObject
		-- Check to see if any data is saved
		local saveData = DataStore:GetAsync(userId);
		
		-- Save userId as a variable so that the save can be indexed to a client identifier 
		local object = {
			userId = userId,
			saved = false,
			
			-- If no save data exists, create empty data object
			values = saveData or DataObject.empty(),
		};
		
		-- Set metatable of object to DataObject template
		setmetatable(object, DataObject);
		
		return object;
	end,	
};

-- Redirect any index made to DataObject to instead look at "values". i.e; data.level -> data.values.level, unless it does not exist, then go back to default __index method
-- Same for player object
function DataObject:__index(key)	
	-- Rawget values to prevent C stack overflow
	local values = rawget(self, "values");
	
	-- Return values
	if (values[key]) then return values[key] end;
	return rawget(self, key);
end

function DataObject:__newindex(key, value)
	-- If the data has already been saved, make it so it cannot be updated after that
	if (self.saved) then return end;
	
	-- Redirect to values or player
	if (self.values[key]) then 
		self.values[key] = value;
	end
	
	-- Set key to nil so this function is triggered if same value is updated again
	rawset(self, key, nil);
end

-- Saves data to data store
function DataObject:Save()
	-- If the data has already been saved, and for some reason this is called again, it will not clog the data store save async queue.
	if (self.saved) then return end;
	
	-- Save data
	DataStore:SetAsync(self.userId, self.values);
	
	-- toggle save
	self.saved = true;
end

-- Player Object Construction
local ClientObject;
ClientObject = {
	new = function(client: Player): Client
		local object = {
			client = client, 
			data = DataObject.new(client.UserId),
		} :: Client;
		
		-- Set the metatable of our object to the ClientObject template
		setmetatable(object, ClientObject);
		
		return object;
	end,	
};

-- Redirect index to go directly to data table, this also makes it so any methods of DataObject are inherited to ClientObject
function ClientObject:__index(key)
	-- Rawget values to prevent C stack overflow
	local data = rawget(self, "data");
	local client = rawget(self, "client");
	
	-- See if methods exist in members of ClientObject
	if (getmetatable(data)[key]) then return getmetatable(data)[key] end;

	-- Because the Player object is an instance, indexing a member that doesnt exist throws an error. To prevent this, use pcall.
	local success, result = pcall(function()
		if (getmetatable(client)[key]) then return getmetatable(client)[key] end;
		if (client[key]) then return client[key] end;
	end)
	if (success) then return result end;
	
	-- Return values
	if (data[key]) then return data[key] end;
	return rawget(self, key);
end

function ClientObject:__newindex(key, value)
	-- If the key exists as a member of the data object, update that member
	if (self.data[key]) then 
		self.data[key] = value; 
		return; 
	end
	
	-- Set key to nil so this function is triggered if same value is updated again
	rawset(self, key, nil);
end

-- Get character of player
function ClientObject:GetCharacter(): Model?
	return self.client.Character;
end

-- Client Service
local ClientService = {
	-- Functions
	GetClients = function(): {number: Client?}
		return Active;
	end,
	GetClient = function(key: number | Player): Client?
		-- Find client based on if key is a player or a number
		if (typeof(key) == "number") then 
			return Active[key];
		elseif (typeof(key) == "Player") then
			return Active[key.UserId];
		end
		
		-- Error if it is neither
		error("GetClient was given parameter that was not either a number (UserId) or Player object.");
	end,
	
	-- Event Listeners
	PlayerJoined = function(client: Player)
		-- Create new player object
		local object = ClientObject.new(client);
		
		-- Save object to Active table
		Active[client.UserId] = object;
	end,
	PlayerRemoving = function(client: Player)
		-- Retrieve Data
		local data = Active[client.UserId];
		
		-- Save Data
		data:Save();
		
		-- Clear storage for player who left
		Active[client.UserId] = nil;
	end,
};

-- Connect events to object
Players.PlayerAdded:Connect(ClientService.PlayerJoined);
Players.PlayerRemoving:Connect(ClientService.PlayerRemoving);

-- Ensure players save data even if game shuts down
game:BindToClose(function()
	-- Because both the Data object and the Player object are redirected to in the __index method of ClientObject, they can be directly referenced and called as methods cleaning this final portion of the code.
	for userId, client: Client in pairs(Active) do
		client:Save();
	end
end)

return ClientService;
