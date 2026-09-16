

if getgenv().CobaltInitialized == true then
	return
end

getgenv().CobaltInitialized = true

type ActorData = {
	Token: string,
	IncomingConnections: boolean,
	IncomingCallbacks: boolean,
	HookIncomingConnections: boolean,
	Outgoing: boolean,

	IgnorePlayerModule: boolean,
	LogBlockedRemotes: boolean,
	AutoIgnoreSpammyEvents: boolean,
	IgnoredRemotesDropdown: { [string]: boolean },

	ExecutorSupport: { [string]: { IsWorking: boolean } },
}

local Data: ActorData = COBALT_ACTOR_DATA

local ChannelId, CurrentActor = ...
if typeof(CurrentActor) == "Instance" then
	CurrentActor = cloneref(CurrentActor)
end

local function ResolveCurrentActor(Origin)
	if Origin and getluastate then
		local Success, LuaStateProxy = pcall(getluastate, Origin)

		
		if Success then
			local Actors = LuaStateProxy:GetActors()
			for _, Actor in Actors do
				if Origin:IsDescendantOf(Actor) then
					return cloneref(Actor)
				end
			end

			if #Actors == 1 then
				return cloneref(Actors[1])
			end
		end
	end

	
	
	local ResolvedActor = get_current_actor and get_current_actor()
	if typeof(ResolvedActor) == "Instance" then
		return cloneref(ResolvedActor)
	end

	
	return CurrentActor
end

local RelayChannel = get_comm_channel(ChannelId)

local wax = {shared = {}}
wax.shared.IS_ACTOR = true
wax.shared.CobaltVerificationToken = Data.Token
local OnUnload
do
	wax.shared.Hooks = {}

	wax.shared.Settings = {
		IgnorePlayerModule = { Value = Data.IgnorePlayerModule },
		LogBlockedRemotes = { Value = Data.LogBlockedRemotes },
		AutoIgnoreSpammyEvents = { Value = Data.AutoIgnoreSpammyEvents },
		IgnoredRemotesDropdown = { Value = Data.IgnoredRemotesDropdown },
		LogRobloxInternalEvents = { Value = Data.LogRobloxInternalEvents },
	}

	wax.shared.SaveManager = {
		GetState = function(Idx, Default)
			return (wax.shared.Settings[Idx] and wax.shared.Settings[Idx].Value) or Data[Idx] or Default
		end,
	}

	wax.shared.Log = {}
	do
		wax.shared.Logs = {
			Outgoing = {},
			Incoming = {},
		}

		wax.shared.NewLog = function(Instance, Type, CallingScript, DebugId)
			local NewLog = wax.shared.Log.new(Instance, Type, 0, CallingScript)
			wax.shared.Logs[Type][DebugId] = NewLog
			return NewLog
		end
	end

	wax.shared.ExecutorSupport = Data.ExecutorSupport
	wax.shared.Communicator = RelayChannel
	wax.shared.ExecutorName = string.split(identifyexecutor(), " ")[1]

	
	for _, Service in pairs({
		"Players",
		"HttpService",
		"RobloxReplicatedStorage",
	}) do
		wax.shared[Service] = cloneref(game:GetService(Service))
	end

	wax.shared.trampoline_call = trampoline_call or (syn and syn.trampoline_call)

	

	local InstanceSerializer = {}
	do
		
		
		local function IsEqualToInstance(Object, ToCompareTo)
			if typeof(Object) ~= "Instance" or typeof(ToCompareTo) ~= "Instance" then return false end

			if rawequal(Object, ToCompareTo) then
				return true
			end

			if wax.shared.ExecutorSupport["compareinstances"].IsWorking then
				return compareinstances(Object, ToCompareTo)
			end

			local ObjectDebugId, ToCompareToDebugId, ShouldCompareDebugIds = nil, nil, false
			do
				local Success, ObjectDebugIdResult = pcall(wax.shared.GetDebugId, Object)
				local Success2, ToCompareToDebugIdResult = pcall(wax.shared.GetDebugId, ToCompareTo)

				if Success and Success2 then
					ObjectDebugId = ObjectDebugIdResult
					ToCompareToDebugId = ToCompareToDebugIdResult
					ShouldCompareDebugIds = true
				end
			end

			if ShouldCompareDebugIds then
				return ObjectDebugId == ToCompareToDebugId
			end

			return false
		end
		

		InstanceSerializer.IsEqualToInstance = IsEqualToInstance
	end
	wax.shared.InstanceSerializer = InstanceSerializer

	local Formatter = {}
	do
		
		
		Formatter.CleanTable = { ['"'] = '\\"', ["\\"] = "\\\\" }
		do
			for i = 0, 31 do
				Formatter.CleanTable[string.char(i)] = "\\" .. string.format("%03d", i)
			end
			for i = 127, 255 do
				Formatter.CleanTable[string.char(i)] = "\\" .. string.format("%03d", i)
			end
		end

		
		local IndentTemplate = string.rep(" ", 4)

		
		function Formatter.FormatLuaString(str)
			return string.gsub(str, '["\\\0-\31\127-\255]', Formatter.CleanTable)
		end

		
		function Formatter.FormatLuaLiteral(Value): string?
			local ValueType = type(Value)
			if ValueType == "string" then
				return `"{Formatter.FormatLuaString(Value)}"`
			elseif ValueType == "number" or ValueType == "boolean" then
				return tostring(Value)
			end

			return nil
		end
		
	end

	
		
		local function FindEventReferenceInTable(
			Table: { [any]: any },
			Instance: Instance,
			Visited: { [any]: boolean }?
		): { any }?
			local Seen = Visited or {}
			if Seen[Table] then
				return nil
			end

			Seen[Table] = true

			for Key, Value in next, Table do
				if
					typeof(Value) == "Instance"
					and InstanceSerializer.IsEqualToInstance(Value, Instance)
					and Formatter.FormatLuaLiteral(Key)
				then
					return { Key }
				end

				if type(Value) == "table" and Formatter.FormatLuaLiteral(Key) then
					local ChildPath = FindEventReferenceInTable(Value, Instance, Seen)
					if ChildPath then
						table.insert(ChildPath, 1, Key)
						return ChildPath
					end
				end
			end

			return nil
		end
	

	
	local RelayConnection
	RelayConnection = RelayChannel.Event:Connect(function(Type, ...)
		if Type == "Unload" then
			RelayConnection:Disconnect()
			wax.shared.Unloaded = true
			for _, Connection in wax.shared.Connections do
				Connection:Disconnect()
			end
			table.clear(wax.shared.Connections)

			if OnUnload then
				OnUnload()
			end
		elseif Type == "MainBlock" then
			local Instance, EventType = ...
			local Log = wax.shared.Logs[EventType][wax.shared.GetDebugId(Instance)]
			if Log then
				Log:Block()
			end
		elseif Type == "MainIgnore" then
			local Instance, EventType = ...
			local Log = wax.shared.Logs[EventType][wax.shared.GetDebugId(Instance)]
			if Log then
				Log:Ignore()
			end
		elseif Type == "MainSettingsSync" then
			local Setting, Value = ...
			if wax.shared.Settings[Setting] then
				wax.shared.Settings[Setting].Value = Value
			end
		elseif Type == "MainCallFiltersSync" then
			wax.shared.CallFilters:ReplaceAll(..., true)
		elseif Type == "InspectIncomingConnections" then
			local Instance, Method, LogIndex, CallIndex = ...
			local Success, Signal = pcall(function()
				return Instance[Method]
			end)
			if not Success or typeof(Signal) ~= "RBXScriptSignal" then
				return
			end

			for _, Connection in getconnections(Signal) do
				if Connection.ForeignState then
					continue
				end

				local Function = typeof(Connection.Function) == "function" and Connection.Function or nil

				local Origin
				local Thread = Connection.Thread
				if Thread and getscriptfromthread then
					Origin = getscriptfromthread(Thread)
				end
				if not Origin and Function then
					local Script = rawget(getfenv(Function), "script")
					if typeof(Script) == "Instance" then
						Origin = Script
					end
				end

				local FixedInfo, CyclicRefs, ContainsCyclicRef = wax.shared.SerializeActorInfo({
					Origin = Origin,
					Function = Function,
					Line = nil,
					IsExecutor = Function and isexecutorclosure(Function) or false,
					IsActor = true,
					Actor = ResolveCurrentActor(Origin),
				})

				RelayChannel:Fire(
					"IncomingConnectionMetadata",
					Instance,
					LogIndex,
					CallIndex,
					FixedInfo,
					CyclicRefs,
					ContainsCyclicRef
				)
			end
		elseif Type == "ResolveEventReference" then
			local Hash, Instance, IsExecutor, RequestId = ...
			local Retrieved = nil

			if filtergc then
				Retrieved = filtergc("function", {
					Hash = Hash,
					IgnoreExecutor = not IsExecutor,
				}, true)
			else
				for _, Func in getgc() do
					if typeof(Func) ~= "function" then
						continue
					end

					if IsExecutor and not isexecutorclosure(Func) then
						continue
					end

					if getfunctionhash(Func) == Hash then
						Retrieved = Func
						break
					end
				end
			end

			if not Retrieved then
				RelayChannel:Fire("ResolveEventReferenceResponse", RequestId, nil)
				return
			end

			local UpvaluePath = FindEventReferenceInTable(debug.getupvalues(Retrieved), Instance)

			if not UpvaluePath then
				RelayChannel:Fire("ResolveEventReferenceResponse", RequestId, nil)
				return
			end

			local UpvalueIndex = table.remove(UpvaluePath, 1)
			RelayChannel:Fire("ResolveEventReferenceResponse", RequestId, {
				Hash = Hash,
				Index = UpvalueIndex,
				Path = UpvaluePath,
			})
		end
	end)

	wax.shared.Unloaded = false
end


do
	local Connections = {}

	local function Connect(Connection)
		table.insert(Connections, Connection)
		return Connection
	end

	local function Disconnect(Connection)
		Connection:Disconnect()

		local Index = table.find(Connections, Connection)
		if Index then
			table.remove(Connections, Index)
		end

		return true
	end

	wax.shared.Connections = Connections
	wax.shared.Connect = Connect
	wax.shared.Disconnect = Disconnect

	wax.shared.Connect = Connect
end



wax.shared.LocalPlayer = wax.shared.Players.LocalPlayer
local ContendingPlayerScripts =
	cloneref(wax.shared.LocalPlayer:QueryDescendants("PlayerScripts")[1] or wax.shared.LocalPlayer)
if ContendingPlayerScripts:IsA("PlayerScripts") then
	wax.shared.PlayerScripts = ContendingPlayerScripts
else
	wax.shared.PlayerScripts = nil

	local ChildAddedConnection
	ChildAddedConnection = wax.shared.Connect(wax.shared.LocalPlayer.ChildAdded:Connect(function(Child)
		if Child:IsA("PlayerScripts") then
			wax.shared.PlayerScripts = cloneref(Child)
			wax.shared.Disconnect(ChildAddedConnection)
		end
	end))
end



wax.shared.restorefunction = function(Function: (...any) -> ...any, Silent: boolean?)
	local Original = wax.shared.Hooks[Function]

	if Silent and not Original then
		return
	end

	assert(Original, "Function not hooked")

	if restorefunction and isfunctionhooked(Function) then
		restorefunction(Function)
	else
		wax.shared.Hooking.HookFunction(Function, Original)
	end

	wax.shared.Hooks[Function] = nil
end
wax.shared.getrawmetatable = wax.shared.ExecutorSupport["getrawmetatable"].IsWorking
		and (getrawmetatable or debug.getmetatable)
	or function()
		return setmetatable({}, {
			__index = function()
				return function() end
			end,
		})
	end

local RawGetDebugId = clonefunction and clonefunction(game.GetDebugId) or game.GetDebugId
wax.shared.GetDebugId = function(Instance)
	local identity = getthreadidentity()
	setthreadidentity(8)
	local id = RawGetDebugId(Instance)
	setthreadidentity(identity)
	return id
end

wax.shared.newcclosure = wax.shared.ExecutorName == "AWP"
		and function(f, name)
			local env = getfenv(f)
			local x = setmetatable({
				__F = f,
			}, {
				__index = env,
				__newindex = env,
			})

			local nf = function(...)
				return __F(...)
			end

			setfenv(nf, x) 
			return newcclosure(nf, name)
		end
	or newcclosure



do
	local Hooking = {}

	Hooking.HookFunction = function(Original, Replacement, Filter)
		if
			wax.shared.IsUsingOthHooks
			and iscclosure(Original)
		then
			return oth.hook(Original, Replacement, Filter)
		end

		if islclosure(Replacement) then
			Replacement = wax.shared.newcclosure(Replacement)
		end

		if not wax.shared.ExecutorSupport["hookfunction"].IsWorking then
			return Original
		end

		return hookfunction(Original, Replacement, Filter)
	end

	Hooking.HookMetaMethod = function(object, method, hook, filter)
		local Metatable = wax.shared.getrawmetatable(object)
		local originalMethod = rawget(Metatable, method)

		assert(typeof(originalMethod) == "function", `{method} is not a function in the metatable of {object}`)

		if wax.shared.IsUsingOthHooks then
			return oth.hook(originalMethod, hook, filter)
		end

		if islclosure(hook) then
			hook = wax.shared.newcclosure(hook)
		end

		if
			not wax.shared.ExecutorSupport["hookmetamethod"].IsWorking
			and wax.shared.ExecutorSupport["getrawmetatable"].IsWorking
		then
			setreadonly(Metatable, false)
			rawset(Metatable, method, hook)
			setreadonly(Metatable, true)

			return originalMethod
		end

		if not wax.shared.ExecutorSupport["hookmetamethod"].IsWorking then
			if method == "__index" then
				local _, Metamethod = xpcall(function()
					return object[tostring(math.random())]
				end, function(err)
					return debug.info(2, "f")
				end)

				return Metamethod
			elseif method == "__newindex" then
				local _, Metamethod = xpcall(function()
					object[tostring(math.random())] = true
				end, function(err)
					return debug.info(2, "f")
				end)

				return Metamethod
			elseif method == "__namecall" then
				local _, Metamethod = xpcall(function()
					object:Mustard()
				end, function(err)
					return debug.info(2, "f")
				end)

				return Metamethod
			end

			return nil
		end

		if filter then
			return hookmetamethod(object, method, hook, true, filter)
		end
		
		return hookmetamethod(object, method, hook)
	end

	wax.shared.Hooking = Hooking
end



do
	

	local TableProxy = {}

	local UNPACK_CHUNK = 7997
	local SAFE_LIMIT = 12000

	function TableProxy.Pack(...)
	    return { n = select("#", ...), ... }
	end

	function TableProxy.Unpack(Tbl, I, J)
	    I = I or 1
	    J = J or Tbl.n or #Tbl

	    if J - I + 1 > SAFE_LIMIT then
	        J = I + SAFE_LIMIT - 1
	    end

	    if J < I then
	        return
	    end

	    if J - I + 1 <= UNPACK_CHUNK then
	        return table.unpack(Tbl, I, J)
	    end

	    return Tbl[I], TableProxy.Unpack(Tbl, I + 1, J)
	end

	wax.shared.SafePack = TableProxy
end



do
	
	type SchemaKind = "Any" | "Type" | "Literal" | "Enum" | "Array" | "Object" | "Union"
	type Refinement = {
		Predicate: (any) -> boolean,
		Message: string,
	}
	type SchemaNode = {
		Kind: SchemaKind,
		ExpectedType: string?,
		Literal: any?,
		Values: { any }?,
		Item: SchemaNode?,
		Shape: { [any]: SchemaNode }?,
		Schemas: { SchemaNode }?,
		IsOptional: boolean?,
		HasDefault: boolean?,
		DefaultValue: any?,
		Refinements: { Refinement }?,
		Minimum: number?,
		Maximum: number?,
		Integer: boolean?,
	}

	
	local Node = {}
	Node.__index = Node

	local Schema = {}

	
	local function CloneValue(Value)
		if type(Value) ~= "table" then
			return Value
		end

		local Copy = {}
		for Key, Child in Value do
			Copy[CloneValue(Key)] = CloneValue(Child)
		end
		return Copy
	end

	local function CloneNode(self: SchemaNode): SchemaNode
		local Copy = table.clone(self)
		Copy.Refinements = self.Refinements and table.clone(self.Refinements) or nil
		return setmetatable(Copy, Node) :: any
	end

	local function NewNode(Kind: SchemaKind, Data: { [any]: any }?): SchemaNode
		local NewSchema = Data and table.clone(Data) or {}
		NewSchema.Kind = Kind
		return setmetatable(NewSchema, Node) :: any
	end

	local function AddError(Errors: { string }, Path: string, Message: string)
		table.insert(Errors, `{Path}: {Message}`)
	end

	local function ChildPath(Path: string, Key: any): string
		if type(Key) == "number" then
			return `{Path}[{Key}]`
		end
		return Path == "" and tostring(Key) or `{Path}.{Key}`
	end

	local function IsSchema(Value): boolean
		return type(Value) == "table" and getmetatable(Value) == Node
	end

	local function ValidateNode(CurrentSchema: SchemaNode, Value: any, Path: string, Errors: { string }): (boolean, any)
		if Value == nil then
			if CurrentSchema.HasDefault then
				return true, CloneValue(CurrentSchema.DefaultValue)
			end
			if CurrentSchema.IsOptional then
				return true, nil
			end

			AddError(Errors, Path, "is required")
			return false, nil
		end

		local IsValid = true
		local Output = Value
		local Kind = CurrentSchema.Kind

		if Kind == "Type" then
			IsValid = typeof(Value) == CurrentSchema.ExpectedType
			if not IsValid then
				AddError(Errors, Path, `expected {CurrentSchema.ExpectedType}, got {typeof(Value)}`)
			end
		elseif Kind == "Literal" then
			IsValid = Value == CurrentSchema.Literal
			if not IsValid then
				AddError(Errors, Path, `expected {tostring(CurrentSchema.Literal)}`)
			end
		elseif Kind == "Enum" then
			IsValid = false
			for _, Option in CurrentSchema.Values or {} do
				if Value == Option then
					IsValid = true
					break
				end
			end
			if not IsValid then
				local Options = {}
				for _, Option in CurrentSchema.Values or {} do
					table.insert(Options, tostring(Option))
				end
				AddError(Errors, Path, `expected one of {table.concat(Options, ", ")}`)
			end
		elseif Kind == "Array" then
			if type(Value) ~= "table" then
				AddError(Errors, Path, `expected table, got {typeof(Value)}`)
				IsValid = false
			else
				Output = {}
				for Index, Child in Value do
					if type(Index) ~= "number" or Index % 1 ~= 0 or Index < 1 then
						AddError(Errors, Path, "expected an array with positive integer keys")
						IsValid = false
						continue
					end

					local ChildValid, ChildOutput = ValidateNode(CurrentSchema.Item :: SchemaNode, Child, ChildPath(Path, Index), Errors)
					IsValid = ChildValid and IsValid
					if ChildValid then
						Output[Index] = ChildOutput
					end
				end
			end
		elseif Kind == "Object" then
			if type(Value) ~= "table" then
				AddError(Errors, Path, `expected table, got {typeof(Value)}`)
				IsValid = false
			else
				Output = {}
				for Key, ChildSchema in CurrentSchema.Shape or {} do
					local ChildValid, ChildOutput = ValidateNode(ChildSchema, Value[Key], ChildPath(Path, Key), Errors)
					IsValid = ChildValid and IsValid
					if ChildOutput ~= nil then
						Output[Key] = ChildOutput
					end
				end
			end
		elseif Kind == "Union" then
			IsValid = false
			for _, ChildSchema in CurrentSchema.Schemas or {} do
				local ChildErrors = {}
				local ChildValid, ChildOutput = ValidateNode(ChildSchema, Value, Path, ChildErrors)
				if ChildValid then
					IsValid = true
					Output = ChildOutput
					break
				end
			end
			if not IsValid then
				AddError(Errors, Path, "did not match any allowed schema")
			end
		end

		if not IsValid then
			return false, nil
		end

		if type(Output) == "number" then
			if CurrentSchema.Integer and Output % 1 ~= 0 then
				AddError(Errors, Path, "expected an integer")
				IsValid = false
			end
			if CurrentSchema.Minimum ~= nil and Output < CurrentSchema.Minimum then
				AddError(Errors, Path, `must be at least {CurrentSchema.Minimum}`)
				IsValid = false
			end
			if CurrentSchema.Maximum ~= nil and Output > CurrentSchema.Maximum then
				AddError(Errors, Path, `must be at most {CurrentSchema.Maximum}`)
				IsValid = false
			end
		end

		for _, Refinement in CurrentSchema.Refinements or {} do
			local Success, Result = pcall(Refinement.Predicate, Output)
			if not Success or not Result then
				AddError(Errors, Path, Refinement.Message)
				IsValid = false
			end
		end

		if not IsValid then
			return false, nil
		end
		return true, Output
	end

	
	function Node:optional(): SchemaNode
		local Copy = CloneNode(self)
		Copy.IsOptional = true
		return Copy
	end

	function Node:default(Value: any): SchemaNode
		local Copy = CloneNode(self)
		Copy.HasDefault = true
		Copy.DefaultValue = Value
		return Copy
	end

	function Node:refine(Predicate: (any) -> boolean, Message: string?): SchemaNode
		assert(type(Predicate) == "function", "Schema refinement must be a function")
		local Copy = CloneNode(self)
		Copy.Refinements = Copy.Refinements or {}
		table.insert(Copy.Refinements, {
			Predicate = Predicate,
			Message = Message or "failed refinement",
		})
		return Copy
	end

	function Node:integer(): SchemaNode
		assert(self.Kind == "Type" and self.ExpectedType == "number", "integer() can only be used on number schemas")
		local Copy = CloneNode(self)
		Copy.Integer = true
		return Copy
	end

	function Node:min(Value: number): SchemaNode
		assert(self.Kind == "Type" and self.ExpectedType == "number", "min() can only be used on number schemas")
		local Copy = CloneNode(self)
		Copy.Minimum = Value
		return Copy
	end

	function Node:max(Value: number): SchemaNode
		assert(self.Kind == "Type" and self.ExpectedType == "number", "max() can only be used on number schemas")
		local Copy = CloneNode(self)
		Copy.Maximum = Value
		return Copy
	end

	
	function Schema.any(): SchemaNode
		return NewNode("Any")
	end

	function Schema.type(ExpectedType: string): SchemaNode
		assert(type(ExpectedType) == "string", "Schema type must be a string")
		return NewNode("Type", { ExpectedType = ExpectedType })
	end

	function Schema.string(): SchemaNode
		return Schema.type("string")
	end

	function Schema.number(): SchemaNode
		return Schema.type("number")
	end

	function Schema.boolean(): SchemaNode
		return Schema.type("boolean")
	end

	function Schema.table(): SchemaNode
		return Schema.type("table")
	end

	function Schema.callback(): SchemaNode
		return Schema.type("function")
	end

	function Schema.instance(ClassName: string?): SchemaNode
		local InstanceSchema = Schema.type("Instance")
		if ClassName then
			return InstanceSchema:refine(function(Value)
				return Value:IsA(ClassName)
			end, `expected an Instance that is a {ClassName}`)
		end
		return InstanceSchema
	end

	function Schema.literal(Value: any): SchemaNode
		assert(Value ~= nil, "Schema literal cannot be nil; use optional() instead")
		return NewNode("Literal", { Literal = Value })
	end

	function Schema.enum(Values: { any }): SchemaNode
		assert(type(Values) == "table" and #Values > 0, "Schema enum requires at least one value")
		return NewNode("Enum", { Values = table.clone(Values) })
	end

	function Schema.array(ItemSchema: SchemaNode): SchemaNode
		assert(IsSchema(ItemSchema), "Schema array requires an item schema")
		return NewNode("Array", { Item = ItemSchema })
	end

	function Schema.object(Shape: { [any]: SchemaNode }): SchemaNode
		assert(type(Shape) == "table", "Schema object requires a shape")
		for Key, ChildSchema in Shape do
			assert(IsSchema(ChildSchema), `Schema object field {tostring(Key)} must be a schema`)
		end
		return NewNode("Object", { Shape = table.clone(Shape) })
	end

	function Schema.union(Schemas: { SchemaNode }): SchemaNode
		assert(type(Schemas) == "table" and #Schemas > 0, "Schema union requires at least one schema")
		for _, ChildSchema in Schemas do
			assert(IsSchema(ChildSchema), "Schema union entries must be schemas")
		end
		return NewNode("Union", { Schemas = table.clone(Schemas) })
	end

	
	function Schema.Validate(DataSchema: SchemaNode, Value: any): (boolean, any, { string })
		assert(IsSchema(DataSchema), "ValidateSchema requires a schema created by Validation.Schema")
		local Errors = {}
		local IsValid, Output = ValidateNode(DataSchema, Value, "Value", Errors)
		return IsValid, Output, Errors
	end

	wax.shared.ValidationSchema = Schema
end



do
	
	local Schema = wax.shared.ValidationSchema or require(script.Schema)

	
	local Validation = {
		Schema = Schema,
	}

	
	function Validation.FillTemplate(Data, Template)
		local NewData = {}
		for Key, Value in Template do
			if Data[Key] == nil or typeof(Data[Key]) ~= typeof(Value) then
				NewData[Key] = Value
			else
				NewData[Key] = Data[Key]
			end
		end

		return NewData
	end

	function Validation.ValidateSchema(Data, DataSchema)
		return Schema.Validate(DataSchema, Data)
	end

	wax.shared.Validation = Validation
end



do
	local Operators = {}

	local Registry = {
		Equals = {
			Text = "==",
			AllowedTypes = { boolean = true, number = true, string = true },
			Evaluate = function(Value, Expected)
				return Value == Expected
			end,
		},
		NotEquals = {
			Text = "~=",
			AllowedTypes = { boolean = true, number = true, string = true },
			Evaluate = function(Value, Expected)
				return Value ~= Expected
			end,
		},
		LessThan = {
			Text = "<",
			NumericComparison = true,
			AllowedTypes = { number = true },
			Evaluate = function(Value, Expected)
				return typeof(Value) == "number" and typeof(Expected) == "number" and Value < Expected
			end,
		},
		LessThanOrEqual = {
			Text = "<=",
			NumericComparison = true,
			AllowedTypes = { number = true },
			Evaluate = function(Value, Expected)
				return typeof(Value) == "number" and typeof(Expected) == "number" and Value <= Expected
			end,
		},
		GreaterThan = {
			Text = ">",
			NumericComparison = true,
			AllowedTypes = { number = true },
			Evaluate = function(Value, Expected)
				return typeof(Value) == "number" and typeof(Expected) == "number" and Value > Expected
			end,
		},
		GreaterThanOrEqual = {
			Text = ">=",
			NumericComparison = true,
			AllowedTypes = { number = true },
			Evaluate = function(Value, Expected)
				return typeof(Value) == "number" and typeof(Expected) == "number" and Value >= Expected
			end,
		},
		Contains = {
			Text = "Contains",
			SummaryText = "contains",
			AllowedTypes = { string = true },
			Evaluate = function(Value, Expected)
				return typeof(Value) == "string"
					and typeof(Expected) == "string"
					and string.find(Value, Expected, 1, true) ~= nil
			end,
		},
		StartsWith = {
			Text = "Starts with",
			SummaryText = "starts with",
			AllowedTypes = { string = true },
			Evaluate = function(Value, Expected)
				return typeof(Value) == "string"
					and typeof(Expected) == "string"
					and string.sub(Value, 1, #Expected) == Expected
			end,
		},
		EndsWith = {
			Text = "Ends with",
			SummaryText = "ends with",
			AllowedTypes = { string = true },
			Evaluate = function(Value, Expected)
				return typeof(Value) == "string"
					and typeof(Expected) == "string"
					and (Expected == "" or string.sub(Value, -#Expected) == Expected)
			end,
		},
		TypeIs = {
			Text = "Type",
			SummaryText = "type",
			Evaluate = function(Value, Expected)
				return typeof(Value) == tostring(Expected)
			end,
		},
	}

	local Order = {
		"Equals",
		"NotEquals",
		"LessThan",
		"LessThanOrEqual",
		"GreaterThan",
		"GreaterThanOrEqual",
		"Contains",
		"StartsWith",
		"EndsWith",
		"TypeIs",
	}

	local TypeNames = {
		"nil",
		"boolean",
		"number",
		"string",
		"table",
		"function",
		"thread",
		"userdata",
		"Instance",
		"EnumItem",
		"RBXScriptSignal",
		"RBXScriptConnection",
		"Vector2",
		"Vector3",
		"CFrame",
		"Color3",
		"BrickColor",
		"UDim",
		"UDim2",
		"Rect",
		"Ray",
		"buffer",
	}

	local TypeNameLookup = {}
	for _, TypeName in TypeNames do
		TypeNameLookup[TypeName] = true
	end

	local function GetSubjectKey(Subject): string
		return if Subject.Type == "ArgumentCount" then "ArgumentCount" else `Argument:{Subject.Index}`
	end

	local function FormatSubject(Subject): string
		return if Subject.Type == "ArgumentCount" then "#Arg" else `Arg[{Subject.Index}]`
	end

	local function GetAndGroupRange(Conditions, Condition)
		local ConditionIndex = table.find(Conditions, Condition)
		if not ConditionIndex then
			return 1, #Conditions
		end

		local FirstIndex = 1
		for Index = ConditionIndex, 2, -1 do
			if Conditions[Index].Join == "Or" then
				FirstIndex = Index
				break
			end
		end

		local LastIndex = #Conditions
		for Index = ConditionIndex + 1, #Conditions do
			if Conditions[Index].Join == "Or" then
				LastIndex = Index - 1
				break
			end
		end

		return FirstIndex, LastIndex
	end

	local function FormatValue(Value): string
		return if typeof(Value) == "string" then `"{Value}"` else tostring(Value)
	end

	function Operators.Get(Operator)
		return Registry[Operator]
	end

	function Operators.GetOptions()
		local Options = {}
		for _, Operator in Order do
			local Definition = Registry[Operator]
			table.insert(Options, {
				Value = Operator,
				Text = Definition.Text,
			})
		end
		return Options
	end

	function Operators.GetTypeNames()
		return table.clone(TypeNames)
	end

	function Operators.IsTypeName(Value): boolean
		return type(Value) == "string" and TypeNameLookup[Value] == true
	end

	function Operators.GetText(Operator, Summary: boolean?): string
		local Definition = Registry[Operator]
		if not Definition then
			return tostring(Operator)
		end
		return Summary and Definition.SummaryText or Definition.Text
	end

	function Operators.FormatValue(Value): string
		return FormatValue(Value)
	end

	function Operators.IsNumericComparison(Operator): boolean
		local Definition = Registry[Operator]
		return Definition ~= nil and Definition.NumericComparison == true
	end

	function Operators.Evaluate(Operator, Value, Expected): boolean
		local Definition = Registry[Operator]
		return Definition ~= nil and Definition.Evaluate(Value, Expected) or false
	end

	function Operators.ResolveSubject(Subject, Arguments)
		if Subject.Type == "ArgumentCount" then
			return Arguments.n or #Arguments
		end

		return Arguments[Subject.Index]
	end

	function Operators.MatchesCondition(Condition, Arguments): boolean
		return Operators.Evaluate(Condition.Operator, Operators.ResolveSubject(Condition.Subject, Arguments), Condition.Value)
	end

	function Operators.Matches(Conditions, ResolveValue): boolean
		if #Conditions == 0 then
			return true
		end

		local AnyGroupMatches = false
		local CurrentGroupMatches = Operators.Evaluate(
			Conditions[1].Operator,
			ResolveValue(Conditions[1]),
			Conditions[1].Value
		)
		for Index = 2, #Conditions do
			local Condition = Conditions[Index]
			local Matches = Operators.Evaluate(Condition.Operator, ResolveValue(Condition), Condition.Value)
			if Condition.Join == "Or" then
				AnyGroupMatches = AnyGroupMatches or CurrentGroupMatches
				CurrentGroupMatches = Matches
			else
				CurrentGroupMatches = CurrentGroupMatches and Matches
			end
		end

		return AnyGroupMatches or CurrentGroupMatches
	end

	function Operators.MatchesConditions(Conditions, Arguments): boolean
		return Operators.Matches(Conditions, function(Condition)
			return Operators.ResolveSubject(Condition.Subject, Arguments)
		end)
	end

	function Operators.GetConditionType(Conditions, Condition): string?
		if Condition.Subject.Type == "ArgumentCount" then
			return "number"
		end

		local SubjectKey = GetSubjectKey(Condition.Subject)
		local FirstIndex, LastIndex = GetAndGroupRange(Conditions, Condition)
		for Index = FirstIndex, LastIndex do
			local OtherCondition = Conditions[Index]
			if
				OtherCondition ~= Condition
				and GetSubjectKey(OtherCondition.Subject) == SubjectKey
				and OtherCondition.Operator == "TypeIs"
			then
				return tostring(OtherCondition.Value)
			end
		end

		if Condition.Operator == "TypeIs" then
			return tostring(Condition.Value)
		end

		local ValueType = typeof(Condition.Value)
		if ValueType == "boolean" or ValueType == "number" then
			return ValueType
		end

		for Index = FirstIndex, LastIndex do
			local OtherCondition = Conditions[Index]
			local OtherValueType = typeof(OtherCondition.Value)
			if
				OtherCondition ~= Condition
				and GetSubjectKey(OtherCondition.Subject) == SubjectKey
				and (OtherValueType == "boolean" or OtherValueType == "number")
			then
				return OtherValueType
			end
		end

		return if ValueType == "string" then "string" else nil
	end

	function Operators.IsAllowed(Conditions, Condition, Operator): boolean
		if Operator == "TypeIs" then
			return Condition.Subject.Type == "Argument"
		end

		local Definition = Registry[Operator]
		if not Definition then
			return false
		end

		local ConditionType = Operators.GetConditionType(Conditions, Condition)
		return ConditionType == nil or Definition.AllowedTypes[ConditionType] == true
	end

	function Operators.IsConditionValid(Conditions, Condition): boolean
		local Definition = Registry[Condition.Operator]
		if not Definition then
			return false
		end

		if Condition.Operator == "TypeIs" then
			return Condition.Subject.Type == "Argument" and Operators.IsTypeName(Condition.Value)
		end

		local ConditionType = Operators.GetConditionType(Conditions, Condition)
		return ConditionType ~= nil
			and Definition.AllowedTypes ~= nil
			and Definition.AllowedTypes[ConditionType] == true
			and typeof(Condition.Value) == ConditionType
	end

	local function NumericConditionsConflict(First, Second): boolean
		if typeof(First.Value) ~= "number" or typeof(Second.Value) ~= "number" then
			return false
		end

		if First.Operator == "Equals" and Operators.IsNumericComparison(Second.Operator) then
			return not Operators.Evaluate(Second.Operator, First.Value, Second.Value)
		elseif Second.Operator == "Equals" and Operators.IsNumericComparison(First.Operator) then
			return not Operators.Evaluate(First.Operator, Second.Value, First.Value)
		elseif not Operators.IsNumericComparison(First.Operator) or not Operators.IsNumericComparison(Second.Operator) then
			return false
		end

		local FirstIsLower = First.Operator == "GreaterThan" or First.Operator == "GreaterThanOrEqual"
		local SecondIsLower = Second.Operator == "GreaterThan" or Second.Operator == "GreaterThanOrEqual"
		if FirstIsLower == SecondIsLower then
			return false
		end

		local Lower = if FirstIsLower then First else Second
		local Upper = if FirstIsLower then Second else First
		return Lower.Value > Upper.Value
			or Lower.Value == Upper.Value and (Lower.Operator == "GreaterThan" or Upper.Operator == "LessThan")
	end

	local function AreInSameAndBranch(Conditions, FirstIndex: number, SecondIndex: number): boolean
		for Index = FirstIndex + 1, SecondIndex do
			if Conditions[Index].Join == "Or" then
				return false
			end
		end
		return true
	end

	function Operators.Validate(Conditions, Adapter)
		local Errors = {}
		local Conflicts = {}
		local GetKey = Adapter and Adapter.GetKey or function(Condition)
			return GetSubjectKey(Condition.Subject)
		end
		local GetLabel = Adapter and Adapter.GetLabel or function(Condition)
			return FormatSubject(Condition.Subject)
		end
		local IsConditionValid = Adapter and Adapter.IsConditionValid or function(Condition)
			return Operators.IsConditionValid(Conditions, Condition)
		end

		local function AddConflict(FirstIndex: number, SecondIndex: number, Message: string)
			Conflicts[FirstIndex] = true
			Conflicts[SecondIndex] = true
			table.insert(Errors, Message)
		end

		for Index, Condition in Conditions do
			if not IsConditionValid(Condition) then
				Conflicts[Index] = true
				table.insert(
					Errors,
					`{GetLabel(Condition)} has a value that is incompatible with {Operators.GetText(Condition.Operator, true)}.`
				)
			end
		end

		for FirstIndex = 1, #Conditions do
			local First = Conditions[FirstIndex]
			for SecondIndex = FirstIndex + 1, #Conditions do
				local Second = Conditions[SecondIndex]
				if Conflicts[FirstIndex] or Conflicts[SecondIndex] then
					continue
				end
				if GetKey(First) ~= GetKey(Second) or not AreInSameAndBranch(Conditions, FirstIndex, SecondIndex) then
					continue
				end
				local SubjectText = GetLabel(First)

				if First.Operator == "Equals" and Second.Operator == "Equals" and First.Value ~= Second.Value then
					AddConflict(FirstIndex, SecondIndex, `{SubjectText} cannot equal both {FormatValue(First.Value)} and {FormatValue(Second.Value)}.`)
				elseif
					First.Operator == "Equals" and Second.Operator == "NotEquals" and First.Value == Second.Value
					or First.Operator == "NotEquals" and Second.Operator == "Equals" and First.Value == Second.Value
				then
					AddConflict(FirstIndex, SecondIndex, `{SubjectText} cannot both equal and not equal {FormatValue(First.Value)}.`)
				elseif First.Operator == "TypeIs" and Second.Operator == "TypeIs" and First.Value ~= Second.Value then
					AddConflict(FirstIndex, SecondIndex, `{SubjectText} cannot have both type {First.Value} and {Second.Value}.`)
				elseif NumericConditionsConflict(First, Second) then
					AddConflict(FirstIndex, SecondIndex, `{SubjectText} cannot satisfy both numeric comparisons.`)
				else
					local TypeCondition
					local OtherCondition
					if First.Operator == "TypeIs" then
						TypeCondition, OtherCondition = First, Second
					elseif Second.Operator == "TypeIs" then
						TypeCondition, OtherCondition = Second, First
					end

					if TypeCondition and OtherCondition and OtherCondition.Operator ~= "TypeIs" then
						local Definition = Registry[OtherCondition.Operator]
						local TypeName = tostring(TypeCondition.Value)
						if Definition and Definition.AllowedTypes and not Definition.AllowedTypes[TypeName] then
							AddConflict(FirstIndex, SecondIndex, `{SubjectText} has type {TypeName}, so it cannot use {Definition.SummaryText or Definition.Text}.`)
						end
					end
				end
			end
		end

		return #Errors == 0, Errors, Conflicts
	end

	wax.shared.CallFilterOperators = Operators
end



do
	local Operators = wax.shared.CallFilterOperators or require("@src/Utils/CallFilter/Operators")

	local RemoteFields = {}

	local RemoteClassOptions = {
		{ Value = "RemoteEvent", Text = "RemoteEvent" },
		{ Value = "RemoteFunction", Text = "RemoteFunction" },
		{ Value = "UnreliableRemoteEvent", Text = "UnreliableRemoteEvent" },
		{ Value = "BindableEvent", Text = "BindableEvent" },
		{ Value = "BindableFunction", Text = "BindableFunction" },
	}

	local Registry = {
		Name = {
			Text = "Name",
			GetValue = function(Remote)
				return Remote.Name
			end,
		},
		ClassName = {
			Text = "Class",
			ValueOptions = RemoteClassOptions,
			GetValue = function(Remote)
				return Remote.ClassName
			end,
		},
		FullName = {
			Text = "Full path",
			GetValue = function(Remote)
				local Success, Result = pcall(Remote.GetFullName, Remote)
				return Success and Result or Remote.Name
			end,
		},
	}

	local Order = { "Name", "ClassName", "FullName" }
	local StringOperators = {
		Equals = true,
		NotEquals = true,
		Contains = true,
		StartsWith = true,
		EndsWith = true,
	}

	function RemoteFields.Get(Field)
		return Registry[Field]
	end

	function RemoteFields.GetOptions()
		local Options = {}
		for _, Field in Order do
			table.insert(Options, {
				Value = Field,
				Text = Registry[Field].Text,
			})
		end
		return Options
	end

	function RemoteFields.GetNames()
		return table.clone(Order)
	end

	function RemoteFields.GetText(Field): string
		local Definition = Registry[Field]
		return Definition and Definition.Text or tostring(Field)
	end

	function RemoteFields.GetValueOptions(Field)
		local Definition = Registry[Field]
		return Definition and Definition.ValueOptions and table.clone(Definition.ValueOptions) or nil
	end

	function RemoteFields.IsValueAllowed(Field, Value): boolean
		local Options = RemoteFields.GetValueOptions(Field)
		if not Options then
			return typeof(Value) == "string"
		end

		for _, Option in Options do
			if Option.Value == Value then
				return true
			end
		end
		return false
	end

	function RemoteFields.IsOperatorAllowed(Operator, Field): boolean
		if Field == "ClassName" then
			return Operator == "Equals" or Operator == "NotEquals"
		end
		return StringOperators[Operator] == true
	end

	function RemoteFields.IsConditionValid(Condition): boolean
		return Registry[Condition.Field] ~= nil
			and RemoteFields.IsOperatorAllowed(Condition.Operator, Condition.Field)
			and RemoteFields.IsValueAllowed(Condition.Field, Condition.Value)
	end

	function RemoteFields.Validate(Conditions)
		return Operators.Validate(Conditions, {
			GetKey = function(Condition)
				return Condition.Field
			end,
			GetLabel = function(Condition)
				return RemoteFields.GetText(Condition.Field)
			end,
			IsConditionValid = RemoteFields.IsConditionValid,
		})
	end

	function RemoteFields.Matches(Conditions, Remote): boolean
		return Operators.Matches(Conditions, function(Condition)
			local Definition = Registry[Condition.Field]
			return Definition and Definition.GetValue(Remote) or nil
		end)
	end

	wax.shared.CallFilterRemoteFields = RemoteFields
end



do
	
	local Validation = wax.shared.Validation or require("@src/Utils/Validation")
	local Operators = wax.shared.CallFilterOperators or require("@src/Utils/CallFilter/Operators")
	local RemoteFields = wax.shared.CallFilterRemoteFields or require("@src/Utils/CallFilter/RemoteFields")

	local Schema = Validation.Schema

	
	local function GetOperatorNames()
		local Names = {}
		for _, Option in Operators.GetOptions() do
			table.insert(Names, Option.Value)
		end
		return Names
	end

	local function IsConditionValueValid(Condition): boolean
		return Operators.IsConditionValid({ Condition }, Condition)
	end

	local function HasNoConditionConflicts(Conditions): boolean
		return Operators.Validate(Conditions)
	end

	
	local Remote = Schema.instance():refine(function(Value)
		return RemoteFields.IsValueAllowed("ClassName", Value.ClassName)
	end, "must be a supported remote")

	local Subject = Schema.object({
		Type = Schema.enum({ "Argument", "ArgumentCount" }),
		Index = Schema.number():integer():min(1):optional(),
	}):refine(function(Value)
		return Value.Type == "ArgumentCount" and Value.Index == nil or Value.Type == "Argument" and Value.Index ~= nil
	end, "must provide an index only for argument subjects")

	local Condition = Schema.object({
		Subject = Subject,
		Operator = Schema.enum(GetOperatorNames()),
		Value = Schema.any():optional(),
		Join = Schema.enum({ "And", "Or" }):optional(),
	}):refine(IsConditionValueValid, "has a value that is incompatible with its operator")

	local ConditionArray = Schema.array(Condition):refine(HasNoConditionConflicts, "contains conflicting conditions")
	local Conditions = ConditionArray:default({})

	local RemoteCondition = Schema.object({
		Field = Schema.enum(RemoteFields.GetNames()),
		Operator = Schema.enum(GetOperatorNames()),
		Value = Schema.string(),
		Join = Schema.enum({ "And", "Or" }):optional(),
	}):refine(RemoteFields.IsConditionValid, "has an operator or value that is incompatible with its field")

	local RemoteConditions = Schema.array(RemoteCondition):refine(function(Value)
		return #Value > 0 and RemoteFields.Validate(Value)
	end, "must contain at least one non-conflicting remote condition")

	local Target = Schema.union({
		Schema.object({
			Type = Schema.literal("Instance"),
			Remote = Remote,
		}),
		Schema.object({
			Type = Schema.literal("Query"),
			Conditions = RemoteConditions,
		}),
	})

	local Filter = Schema.object({
		Id = Schema.string():optional(),
		Enabled = Schema.boolean():default(true),
		Target = Target,
		Direction = Schema.enum({ "Outgoing", "Incoming", "Any" }),
		Conditions = Conditions,
		Action = Schema.enum({ "Ignore", "Block", "Highlight" }):default("Ignore"),
	})

	local Update = Schema.object({
		Enabled = Schema.boolean():optional(),
		Target = Target:optional(),
		Direction = Schema.enum({ "Outgoing", "Incoming", "Any" }):optional(),
		Conditions = ConditionArray:optional(),
		Action = Schema.enum({ "Ignore", "Block", "Highlight" }):optional(),
	})

	wax.shared.CallFilterSchema = {
		Remote = Remote,
		Subject = Subject,
		Condition = Condition,
		Conditions = Conditions,
		RemoteCondition = RemoteCondition,
		RemoteConditions = RemoteConditions,
		Target = Target,
		Filter = Filter,
		Update = Update,
	}
end



do
	local Operators = wax.shared.CallFilterOperators or require("@src/Utils/CallFilter/Operators")
	local InstanceSerializer = wax.shared.InstanceSerializer or require("@src/Utils/CodeGen/Serializer/Instance")
	local Validation = wax.shared.Validation or require("@src/Utils/Validation")
	local CallFilterSchema = wax.shared.CallFilterSchema or require("@src/Utils/CallFilter/Schema")
	local RemoteFields = wax.shared.CallFilterRemoteFields or require("@src/Utils/CallFilter/RemoteFields")

	local CallFilters = {
		Items = {},
		ById = {},
		Listeners = {},
	}

	local ActionPriorities = {
		Highlight = 1,
		Ignore = 2,
		Block = 3,
	}

	local function Validate(Data, DataSchema, Context: string)
		local IsValid, Result, Errors = Validation.ValidateSchema(Data, DataSchema)
		assert(IsValid, `{Context}: {Errors[1] or "validation failed"}`)
		return Result
	end

	local function CopyFilter(Filter)
		local Copy = table.clone(Filter)
		Copy.Conditions = {}

		for _, Condition in Filter.Conditions or {} do
			local ConditionCopy = table.clone(Condition)
			ConditionCopy.Subject = table.clone(Condition.Subject)
			table.insert(Copy.Conditions, ConditionCopy)
		end

		Copy.Target = table.clone(Filter.Target)
		if Filter.Target.Type == "Query" then
			Copy.Target.Conditions = {}
			for _, Condition in Filter.Target.Conditions do
				table.insert(Copy.Target.Conditions, table.clone(Condition))
			end
		end

		Copy.Enabled = Filter.Enabled ~= false
		return Copy
	end

	local function EmitChanged()
		local Snapshot = CallFilters:GetAll()
		for Listener in CallFilters.Listeners do
			if task then
				task.spawn(Listener, Snapshot)
			else
				Listener(Snapshot)
			end
		end
	end

	function CallFilters:GetAll()
		local Filters = {}
		for _, Filter in self.Items do
			table.insert(Filters, CopyFilter(Filter))
		end
		return Filters
	end

	function CallFilters:Get(Id: string)
		local Filter = self.ById[Id]
		return Filter and CopyFilter(Filter) or nil
	end

	function CallFilters:Add(Filter)
		local Copy = Validate(Filter, CallFilterSchema.Filter, "Invalid call filter")
		Copy.Id = Copy.Id or wax.shared.HttpService:GenerateGUID(false)
		assert(not self.ById[Copy.Id], `A call filter with id {Copy.Id} already exists`)

		table.insert(self.Items, Copy)
		self.ById[Copy.Id] = Copy
		EmitChanged()
		return CopyFilter(Copy)
	end

	function CallFilters:Update(Id: string, Changes)
		local Filter = self.ById[Id]
		if not Filter then
			return nil
		end

		local ValidChanges = Validate(Changes, CallFilterSchema.Update, "Invalid call filter update")
		local Updated = CopyFilter(Filter)
		for Key, Value in ValidChanges do
			Updated[Key] = Value
		end
		Updated = Validate(Updated, CallFilterSchema.Filter, "Invalid updated call filter")

		local Index = table.find(self.Items, Filter)
		if Index then
			self.Items[Index] = Updated
		end
		self.ById[Id] = Updated

		EmitChanged()
		return CopyFilter(Updated)
	end

	function CallFilters:SetEnabled(Id: string, Enabled: boolean)
		return self:Update(Id, { Enabled = Enabled })
	end

	function CallFilters:Remove(Id: string): boolean
		local Filter = self.ById[Id]
		if not Filter then
			return false
		end

		self.ById[Id] = nil
		local Index = table.find(self.Items, Filter)
		if Index then
			table.remove(self.Items, Index)
		end
		EmitChanged()
		return true
	end

	function CallFilters:ReplaceAll(Filters, Silent: boolean?)
		local Validated = Validate(Filters or {}, Validation.Schema.array(CallFilterSchema.Filter), "Invalid call filters")
		local SeenIds = {}
		for _, Filter in Validated do
			Filter.Id = Filter.Id or wax.shared.HttpService:GenerateGUID(false)
			assert(not SeenIds[Filter.Id], `A call filter with id {Filter.Id} already exists`)
			SeenIds[Filter.Id] = true
		end

		table.clear(self.Items)
		table.clear(self.ById)
		for _, Filter in Validated do
			table.insert(self.Items, Filter)
			self.ById[Filter.Id] = Filter
		end

		if not Silent then
			EmitChanged()
		end
	end

	function CallFilters:Subscribe(Listener)
		self.Listeners[Listener] = true
		Listener(self:GetAll())

		local Subscription = {}
		function Subscription:Disconnect()
			CallFilters.Listeners[Listener] = nil
		end
		return Subscription
	end

	function CallFilters:Match(Remote: Instance, Direction: string, Arguments)
		local WinningAction
		local WinningFilter
		local WinningPriority = 0

		for _, Filter in self.Items do
			local TargetMatches = if Filter.Target.Type == "Instance"
				then InstanceSerializer.IsEqualToInstance(Filter.Target.Remote, Remote)
				else RemoteFields.Matches(Filter.Target.Conditions, Remote)
			if
				Filter.Enabled
				and (Filter.Direction == "Any" or Filter.Direction == Direction)
				and TargetMatches
				and Operators.MatchesConditions(Filter.Conditions, Arguments)
			then
				local Priority = ActionPriorities[Filter.Action] or 0
				if Priority > WinningPriority then
					WinningAction = Filter.Action
					WinningFilter = Filter
					WinningPriority = Priority
				end
			end
		end

		return WinningAction, WinningFilter and CopyFilter(WinningFilter) or nil
	end

	function CallFilters:Resolve(Remote: Instance, Direction: string, Info)
		local Action, Filter = self:Match(Remote, Direction, Info.Arguments or {})
		if Action == "Highlight" then
			Info.Highlighted = true
			Info.CallFilterId = Filter.Id
		elseif Action then
			Info.CallFilterId = Filter.Id
		end
		return Action, Filter
	end

	wax.shared.CallFilters = CallFilters
end



wax.shared.IsPlayerModule = function(Origin: LocalScript | ModuleScript, Instance: Instance): boolean
	if Instance and Instance.ClassName ~= "BindableEvent" then
		return false
	end

	if not Origin or typeof(Origin) ~= "Instance" or not Origin.IsA(Origin, "LuaSourceContainer") then
		return false
	end

	local PlayerModule = Origin and Origin.FindFirstAncestor(Origin, "PlayerModule") or nil
	if not PlayerModule then
		return false
	end

	if PlayerModule.Parent == nil then
		return true
	end

	if wax.shared.PlayerScripts then
		return compareinstances(PlayerModule.Parent, wax.shared.PlayerScripts)
	end

	return false
end
wax.shared.ShouldIgnore = function(Instance, Origin)
	if not wax.shared.Settings.LogRobloxInternalEvents.Value then
		if Instance.IsDescendantOf(Instance, wax.shared.RobloxReplicatedStorage) then
			return true
		end
	end

	return wax.shared.Settings.IgnoredRemotesDropdown.Value[Instance.ClassName] == true
		or (wax.shared.Settings.IgnorePlayerModule.Value and wax.shared.IsPlayerModule(Origin, Instance))
end



do
	local Log = {}
	Log.__index = Log

	local PendingCallDecisions = setmetatable({}, { __mode = "k" })

	-- `tostring(table)` is used as the pending-decision key and is needed twice per
	-- call (ShouldBlock + Call).  Remembering the key per info table halves that
	-- work and keeps both lookups on the same interned string.
	local CallDecisionKeys = setmetatable({}, { __mode = "k" })

	-- clonefunction() allocates a brand new closure every time it runs, and the
	-- same calling scripts are cloned over and over.  Clones are cached against the
	-- original closure (weak keys: once the game drops the original, the clone goes
	-- with it).
	local FunctionClones = setmetatable({}, { __mode = "k" })

	local function GetDecisionKey(RawInfo): string
		local Key = CallDecisionKeys[RawInfo]
		if not Key then
			Key = tostring(RawInfo)
			CallDecisionKeys[RawInfo] = Key
		end

		return Key
	end

	local function CloneFunction(Function)
		local Cached = FunctionClones[Function]
		if Cached then
			return Cached
		end

		if not clonefunction then
			return Function
		end

		local Clone = clonefunction(Function)
		FunctionClones[Function] = Clone
		return Clone
	end

	--[[
		Call retention limit.

		Every captured call keeps a deep-cloned copy of its arguments alive for the
		rest of the session.  On a chatty game (and especially on a phone, where the
		OS is quick to kill apps that grow) that is unbounded memory growth, so each
		remote keeps at most `MaxCallsPerRemote` calls and drops the oldest ones.
		The limit is configurable in Settings (Capture -> Calls Kept Per Remote).

		`MaxCallsPerRemote` is cached: reading it through SaveManager validates the
		whole schema, which must not happen once per intercepted call.
	]]
	local DefaultMaxCallsPerRemote = 500
	local CallCapSlack = 32
	local CachedCallCap = nil

	local function GetSettingBoolean(Key: string, Default: boolean): boolean
		local Controls = wax.shared.Settings
		local Control = Controls and Controls[Key]
		if Control and Control.Value ~= nil then
			return Control.Value == true
		end

		local SaveManager = wax.shared.SaveManager
		local Success, Value = pcall(function()
			return SaveManager:GetState(Key, Default)
		end)

		return if Success and Value ~= nil then Value == true else Default
	end

	local function GetMaxCallsPerRemote(): number
		local Controls = wax.shared.Settings
		local Control = Controls and Controls["MaxCallsPerRemote"]

		if Control and Control.Value ~= nil then
			local Value = tonumber(Control.Value)
			if Value and Value >= 1 then
				CachedCallCap = math.floor(Value)
				return CachedCallCap
			end
		end

		if CachedCallCap then
			return CachedCallCap
		end

		local SaveManager = wax.shared.SaveManager
		local Success, Value = pcall(function()
			return SaveManager:GetState("MaxCallsPerRemote", DefaultMaxCallsPerRemote)
		end)

		CachedCallCap = math.floor(tonumber(Success and Value or DefaultMaxCallsPerRemote) or DefaultMaxCallsPerRemote)
		if CachedCallCap < 1 then
			CachedCallCap = DefaultMaxCallsPerRemote
		end

		return CachedCallCap
	end

	-- The producer is on a remote hook, while the consumer is the UI heartbeat.
	-- Keep the hand-off bounded and coalesce updates for the same remote.  A noisy
	-- remote therefore costs one small notification per frame, not one table per
	-- packet.
	local MaxPendingNotifications = 256
	local MaxNotificationsPerHeartbeat = 96
	wax.shared.LogNotificationQueue = {
		Items = {},
		Head = 1,
		Tail = 0,
		PendingByLog = setmetatable({}, { __mode = "k" }),
		Dropped = 0,
	}

	local function QueueNotification(LogObject, CallIndex: number, Call)
		local Queue = wax.shared.LogNotificationQueue
		local Existing = Queue.PendingByLog[LogObject]
		if Existing then
			Existing.CallIndex = CallIndex
			Existing.Call = Call or LogObject.Calls[CallIndex]
			Existing.Suppressed = (Existing.Suppressed or 0) + 1
			return
		end

		local Pending = Queue.Tail - Queue.Head + 1
		while Pending >= MaxPendingNotifications do
			local Oldest = Queue.Items[Queue.Head]
			Queue.Items[Queue.Head] = nil
			Queue.Head += 1
			Pending -= 1
			Queue.Dropped += 1
			if Oldest and Oldest.Log then
				Queue.PendingByLog[Oldest.Log] = nil
			end
		end

		if Queue.Head > Queue.Tail then
			table.clear(Queue.Items)
			Queue.Head = 1
			Queue.Tail = 0
		end

		local Notification = {
			Instance = LogObject.Instance,
			Type = LogObject.Type,
			LogIndex = LogObject.Index,
			CallIndex = CallIndex,
			-- Direct references avoid another DebugId lookup on the UI thread.
			Log = LogObject,
			Call = Call or LogObject.Calls[CallIndex],
			Suppressed = 0,
		}
		Queue.Tail += 1
		Queue.Items[Queue.Tail] = Notification
		Queue.PendingByLog[LogObject] = Notification
	end

	local SpamCallCountThreshold = 120
	local SpamTimeWindowSeconds = 1
	local HardCaptureLimitPerRemote = 120
	local HardCaptureLimitGlobal = 600
	local GlobalCaptureWindowStart = 0
	local GlobalCaptureCount = 0
	local AutoIgnoreSpammyEvents = true

	do
		local Success, Value = pcall(function()
			return wax.shared.SaveManager:GetState("AutoIgnoreSpammyEvents", true)
		end)
		if Success then
			AutoIgnoreSpammyEvents = Value == true
		end
	end

	local function ShouldAutoIgnore(): boolean
		local Control = wax.shared.Settings and wax.shared.Settings.AutoIgnoreSpammyEvents
		if Control and Control.Value ~= nil then
			return Control.Value == true
		end
		return AutoIgnoreSpammyEvents
	end

	local function RejectCapture(LogObject, Now: number): boolean
		if Now - LogObject.SpamWindowStart >= SpamTimeWindowSeconds then
			LogObject.SpamWindowStart = Now
			LogObject.SpamCallCount = 0
		end

		if Now - GlobalCaptureWindowStart >= SpamTimeWindowSeconds then
			GlobalCaptureWindowStart = Now
			GlobalCaptureCount = 0
		end

		if LogObject.SpamCallCount >= HardCaptureLimitPerRemote or GlobalCaptureCount >= HardCaptureLimitGlobal then
			LogObject.SuppressedCalls += 1
			if ShouldAutoIgnore() and not LogObject.Ignored then
				LogObject:Ignore()
				local Sonner = wax.shared.Sonner
				if Sonner then
					local InstanceName = LogObject.Instance and LogObject.Instance.Name or "remote"
					pcall(Sonner.info, Sonner, `Ignored {InstanceName} ({LogObject.Type}) after sustained event spam.`)
				end
			end
			return true
		end

		LogObject.SpamCallCount += 1
		GlobalCaptureCount += 1
		return false
	end

	if not wax.shared.IS_ACTOR then
		wax.shared.Connect(wax.shared.RunService.Heartbeat:Connect(function()
			local Queue = wax.shared.LogNotificationQueue
			if Queue.Head > Queue.Tail then
				return
			end

			local Batch = table.create(math.min(MaxNotificationsPerHeartbeat, Queue.Tail - Queue.Head + 1))
			local BatchSize = 0
			while Queue.Head <= Queue.Tail and BatchSize < MaxNotificationsPerHeartbeat do
				local Notification = Queue.Items[Queue.Head]
				Queue.Items[Queue.Head] = nil
				Queue.Head += 1
				if Notification then
					Queue.PendingByLog[Notification.Log] = nil
					BatchSize += 1
					Batch[BatchSize] = Notification
				end
			end

			if Queue.Head > Queue.Tail then
				table.clear(Queue.Items)
				Queue.Head = 1
				Queue.Tail = 0
			end

			if BatchSize > 0 then
				local Communicator = wax.shared.Communicator
				if Communicator then
					Communicator:Fire(Batch)
				end
				table.clear(Batch)
			end
		end))
	end


	local FunctionToMetatadata, FixTable
	do
		if wax.shared.IS_ACTOR then
			local FunctionMetadataCache = setmetatable({}, { __mode = "k" })

			local function CreateTraversalState(Refs)
				return {
					CyclicRefs = Refs or {},
					TableIds = setmetatable({}, { __mode = "k" }),
					Functions = setmetatable({}, { __mode = "k" }),
					NextId = 0,
				}
			end

			local function GenerateId(State)
				State.NextId += 1
				return State.NextId
			end

			FixTable = function(Table, State)
				if not Table then
					return nil
				end

				if not State or not State.CyclicRefs then
					State = CreateTraversalState(State)
				end

				local CyclicRefs = State.CyclicRefs
				local TableId = State.TableIds[Table]
				if not TableId then
					TableId = GenerateId(State)
					State.TableIds[Table] = TableId
				end

				local OutputTable = {}
				CyclicRefs[TableId] = OutputTable

				local ContainsCyclicRef = false

				for Key, Value in next, Table do
					if type(Value) == "table" then
						local ExistingId = State.TableIds[Value]
						if ExistingId then
							ContainsCyclicRef = true

							OutputTable[Key] = {
								__CyclicRef = true,
								__Id = ExistingId,
							}
							continue
						end

						if getmetatable(Value) then
							OutputTable[Key] =
								"Cobalt: Impossible to bridge table with metatable from actor Environment to main Environment"
							continue
						end

						local Result, _, ContainsCyclic = FixTable(Value, State)
						if not Result then
							continue
						end

						OutputTable[Key] = Result
						ContainsCyclicRef = ContainsCyclicRef or ContainsCyclic
					elseif type(Value) == "function" then
						OutputTable[Key] = FunctionToMetatadata(Value, State)
					else
						OutputTable[Key] = Value
					end
				end

				return OutputTable, CyclicRefs, ContainsCyclicRef
			end

			FunctionToMetatadata = function(Function, State)
				if not Function then
					return nil
				end

				if not State or not State.CyclicRefs then
					State = CreateTraversalState()
				end

				local CachedMetadata = FunctionMetadataCache[Function]
				if CachedMetadata then
					return CachedMetadata
				end

				local Metadata = {
					Address = tostring(Function),
					Name = debug.info(Function, "n"),
					Source = debug.info(Function, "s"),
					IsC = iscclosure(Function),
				}

				if State.Functions[Function] then
					Metadata["Recursive"] = true
					Metadata["Validation"] = Data.Token
					Metadata["__Function"] = true

					return Metadata
				end

				State.Functions[Function] = true

				if not iscclosure(Function) then
					Metadata["Upvalues"] = debug.getupvalues and #debug.getupvalues(Function) or 0
					Metadata["Constants"] = debug.getconstants and #debug.getconstants(Function) or 0
					Metadata["Protos"] = debug.getprotos and #debug.getprotos(Function) or 0

					if getfunctionhash then
						Metadata["FunctionHash"] = getfunctionhash(Function)
					end
				end

				
				Metadata["Validation"] = Data.Token
				Metadata["__Function"] = true

				FunctionMetadataCache[Function] = Metadata

				return Metadata
			end
		end
	end


	function DeepClone(OriginalValue, ValueCopies)
		if wax.shared.IS_ACTOR then
			return OriginalValue
		end

		local OriginalType = type(OriginalValue)
		if OriginalType ~= "table" then
			if OriginalType == "string" or OriginalType == "number" or OriginalType == "boolean" or OriginalValue == nil then
				return OriginalValue
			end

			local RobloxType = typeof(OriginalValue)
			if RobloxType == "Instance" then
				return cloneref(OriginalValue)
		
			elseif RobloxType == "userdata" then
				if getmetatable(OriginalValue) then
					return newproxy(true)
				else
					return newproxy()
				end

			elseif RobloxType == "function" then
				return CloneFunction(OriginalValue)
			end

			return OriginalValue
		end

		
		if ValueCopies then
			local CachedValue = ValueCopies[OriginalValue]
			if CachedValue then
				return CachedValue
			end
		else
			ValueCopies = {}
		end

		
		local ShallowCopy = {}
		ValueCopies[OriginalValue] = ShallowCopy

		for Key, Value in next, OriginalValue do
			local ValueType = type(Value)

			if ValueType == "table" then
				ShallowCopy[Key] = DeepClone(Value, ValueCopies)

			elseif ValueType == "userdata" then
				local ValueRobloxType = typeof(Value)

				if ValueRobloxType == "Instance" then
					ShallowCopy[Key] = cloneref(Value)

				elseif ValueRobloxType == "userdata" then
					if getmetatable(Value) then
						ShallowCopy[Key] = newproxy(true)
					else
						ShallowCopy[Key] = newproxy()
					end

				else
					ShallowCopy[Key] = Value
				end

			elseif ValueType == "function" then
				ShallowCopy[Key] = CloneFunction(Value)
		
			else
				ShallowCopy[Key] = Value
			end
		end

		return ShallowCopy
	end

	if wax.shared.IS_ACTOR then
		wax.shared.SerializeActorInfo = function(Info)
			return FixTable(DeepClone(Info))
		end
	end

	function Log.new(Instance, Type, Index, CallingScript)
		local NewLog = setmetatable({
			Instance = Instance,
			Type = Type,
			Index = Index,
			Calls = {},
			GameCalls = {},
			SpamWindowStart = 0,
			SpamCallCount = 0,
			SuppressedCalls = 0,
			Ignored = false,
			Blocked = false,
			Button = nil,
		}, Log)

		return NewLog
	end

	function Log:IsOverSpamThreshold()
		-- Kept for plugins that query the old API.  Capture admission is enforced
		-- centrally in `Log:Call`, even when the optional auto-ignore setting is off.
		return self.SpamCallCount >= SpamCallCountThreshold
	end

	local function RunInterceptors(Interceptors: { (...any) -> ...any }, Info: any, Log): boolean
		for _, Callback in Interceptors do
			local Ok, Result = pcall(Callback, Info, Log.Instance, Log.Type)
			if not Ok then
				warn(`[Cobalt Plugin Interceptor] Error: {Result}`)
			elseif Result == false then
				return true
			end
		end

		return false
	end

	function Log:ShouldBlock(RawInfo, PendingCallDecisionsKey): boolean
		PendingCallDecisionsKey = PendingCallDecisionsKey or GetDecisionKey(RawInfo)

		local Decision = PendingCallDecisions[PendingCallDecisionsKey]
		if Decision then
			return Decision.ShouldBlock
		end

		local FilterAction
		local CallFilters = wax.shared.CallFilters
		do
			if CallFilters then
				FilterAction = CallFilters:Resolve(self.Instance, self.Type, RawInfo)
			end
		end

		local ShouldBlock = RawInfo.Blocked == true or self.Blocked or FilterAction == "Block"
		if ShouldBlock then
			RawInfo.Blocked = true
		end

		PendingCallDecisions[PendingCallDecisionsKey] = {
			FilterAction = FilterAction,
			ShouldBlock = ShouldBlock,
		}
		return ShouldBlock
	end

	--[[
		Keeps at most `MaxCalls` entries by dropping the oldest ones.

		Call indices are the log's public currency (call lists, notifications, the
		file logger), so both the call array and the executor-call index list are
		rebuilt together and stay consistent.
	]]
	function Log:TrimCalls(MaxCalls: number)
		local Calls = self.Calls
		local Total = #Calls
		local RemoveCount = Total - MaxCalls
		if RemoveCount <= 0 then
			return 0
		end

		local Trimmed = table.create(Total - RemoveCount)
		for Index = RemoveCount + 1, Total do
			Trimmed[Index - RemoveCount] = Calls[Index]
		end
		self.Calls = Trimmed

		local GameCalls = self.GameCalls
		local WriteIndex = 1
		for ReadIndex = 1, #GameCalls do
			local Shifted = GameCalls[ReadIndex] - RemoveCount
			if Shifted >= 1 then
				GameCalls[WriteIndex] = Shifted
				WriteIndex += 1
			end
		end

		for Index = WriteIndex, #GameCalls do
			GameCalls[Index] = nil
		end

		return RemoveCount
	end

	function Log:Call(RawInfo): number?
		local PendingCallDecisionsKey = GetDecisionKey(RawInfo)

		local ShouldBlock = self:ShouldBlock(RawInfo, PendingCallDecisionsKey)
		local Decision = PendingCallDecisions[PendingCallDecisionsKey]
		PendingCallDecisions[PendingCallDecisionsKey] = nil

		local ShouldCapture = not self.Ignored and Decision.FilterAction ~= "Ignore"
		do
			if ShouldBlock then
				ShouldCapture = GetSettingBoolean("LogBlockedRemotes", false)
			end

			if RawInfo.Omit then
				ShouldCapture = false
			end
		end

		if not ShouldCapture then
			return nil
		end

		-- Do this before DeepClone.  Cloning arguments is the expensive part of a
		-- capture, and a hard per-remote/global budget prevents one spammy event
		-- from consuming the frame and memory budgets of the whole game.
		if RejectCapture(self, os.clock()) then
			return nil
		end

		local Info = DeepClone(RawInfo)
		Info.CreationTime = tick()

		
		if wax.shared.IS_ACTOR then
			if self.Instance == wax.shared.Communicator then
				return nil
			end

			Info["Actor"] = CurrentActor

			
			local OldArguments = Info.Arguments
			Info.Arguments = {
				Data = OldArguments,
				n = OldArguments.n,
			}

			if Info.InvokeResult then
				local OldInvokeResult = Info.InvokeResult
				Info.InvokeResult = {
					Data = OldInvokeResult,
					n = OldInvokeResult.n,
				}
			end

			local FixedInfo, CyclicRefs, ContainsCyclicRef = FixTable(Info)

			
			local identity = getthreadidentity()
			setthreadidentity(8)
			wax.shared.Communicator.Fire(
				wax.shared.Communicator,
				"ActorCall",
				self.Instance,
				self.Type,
				FixedInfo,
				CyclicRefs,
				ContainsCyclicRef
			)
			setthreadidentity(identity)
			return nil
		end

		
		local PluginManager = wax.shared.CobaltPluginManager
		if PluginManager and PluginManager.HasInterceptors then
			
			local InstanceIntercept = PluginManager.Registry.Interceptors.Instance[self.Instance]
			if InstanceIntercept then
				if InstanceIntercept[self.Type] and RunInterceptors(InstanceIntercept[self.Type], Info, self) then
					return nil
				end
				if InstanceIntercept["All"] and RunInterceptors(InstanceIntercept["All"], Info, self) then
					return nil
				end
			end

			
			local GlobalByType = PluginManager.Registry.Interceptors.Global[self.Type]
			if GlobalByType and RunInterceptors(GlobalByType, Info, self) then
				return nil
			end

			local GlobalAll = PluginManager.Registry.Interceptors.Global["All"]
			if GlobalAll and RunInterceptors(GlobalAll, Info, self) then
				return nil
			end
		end

		
		local Index = #self.Calls + 1
		self.Calls[Index] = Info
		if not Info.IsExecutor then
			table.insert(self.GameCalls, Index)
		end

		-- Trim with a little slack so the rebuild cost is amortised over many calls
		-- instead of running on every single one at the cap.
		local CallCap = GetMaxCallsPerRemote()
		if Index > CallCap + CallCapSlack then
			self:TrimCalls(CallCap)
			Index = #self.Calls
		end

		QueueNotification(self, Index, Info)
		return Index
	end

	function Log:ClearCalls()
		table.clear(self.Calls)
		table.clear(self.GameCalls)
		local Pending = wax.shared.LogNotificationQueue.PendingByLog[self]
		if Pending then
			Pending.Call = nil
			Pending.CallIndex = nil
			wax.shared.LogNotificationQueue.PendingByLog[self] = nil
		end
		self.SpamWindowStart = os.clock()
		self.SpamCallCount = 0
		self.SuppressedCalls = 0
	end

	function Log:Ignore()
		self.Ignored = not self.Ignored

		if not wax.shared.IS_ACTOR then
			if wax.shared.ActorCommunicator then
				pcall(wax.shared.ActorCommunicator.Fire, wax.shared.ActorCommunicator, "MainIgnore", self.Instance, self.Type)
			end

			local IgnoredRemoteList = wax.shared.Settings["IgnoredRemotes"]
			if IgnoredRemoteList then
				if self.Ignored then
					IgnoredRemoteList:AddToList(self)
				else
					IgnoredRemoteList:RemoveFromList(self)
				end
			end
		end
	end

	local ClassesConnectionsToggle = {
		RemoteEvent = "OnClientEvent",
		UnreliableRemoteEvent = "OnClientEvent",
		BindableEvent = "Event",
	}

	function Log:SetConnectionsEnabled(enabled: boolean)
		if not self.Instance or not ClassesConnectionsToggle[self.Instance.ClassName] then
			return
		end

		local ConnectionName = ClassesConnectionsToggle[self.Instance.ClassName]
		if self.Type ~= "Incoming" or not ConnectionName then
			return
		end

		local LoggingFunctions = wax.shared.IncomingLogConnectionFunctions
		for _, Connection in pairs(getconnections(self.Instance[ConnectionName])) do
			if LoggingFunctions and LoggingFunctions[Connection.Function] then
				continue
			end

			if enabled then
				Connection:Enable()
			else
				Connection:Disable()
			end
		end
	end

	function Log:Block()
		if not wax.shared.IS_ACTOR and wax.shared.ActorCommunicator then
			pcall(wax.shared.ActorCommunicator.Fire, wax.shared.ActorCommunicator, "MainBlock", self.Instance, self.Type)
		end

		self.Blocked = not self.Blocked
		self:SetConnectionsEnabled(not self.Blocked)
	end

	function Log:SetButton(Instance, Name, Calls)
		self.Button = {
			Instance = Instance,
			Name = Name,
			Calls = Calls,
		}
	end

	wax.shared.Log = Log
end



do
	
	local function CreateLookupTable(table)
		local LookupTable = {}
		for _, Method in next, table do
			LookupTable[Method] = true
		end
		return LookupTable
	end

	
	local setfenv = setfenv
	local getconnections = wax.shared.ExecutorSupport["getconnections"].IsWorking and getconnections or function() return {} end

	local ClassesToHook = {
		RemoteEvent = "OnClientEvent",
		RemoteFunction = "OnClientInvoke",
		UnreliableRemoteEvent = "OnClientEvent",
		BindableEvent = "Event",
		BindableFunction = "OnInvoke",
	}

	local ConnectionKeys = CreateLookupTable({
		"Connect",
		"ConnectParallel",
		"connect",
		"connectParallel",
		"Once",
	})

	
	local ConnectionsEnabled = false
	local CallbacksEnabled = false
	local ConnectionHookEnabled = false

	
	local LogConnectionFunctions = {}
	local CallbackOwners = setmetatable({}, { __mode = "k" })
	local SignalMapping = setmetatable({}, { __mode = "kv" })
	local ObservedConnectionInstances = setmetatable({}, { __mode = "k" })
	wax.shared.IncomingLogConnectionFunctions = LogConnectionFunctions

	local CobaltObserverEnvironmentKey = "__CobaltIncomingObserver"

	
	type InstancesToHook = RemoteEvent | UnreliableRemoteEvent | RemoteFunction | BindableEvent | BindableFunction
	type MethodsToHook = "OnClientEvent" | "OnClientInvoke" | "Event" | "OnInvoke"
	export type Options = {
		Connections: boolean?,
		Callbacks: boolean?,
		HookConnections: boolean?,
	}

	
	local function GetLog(Instance: InstancesToHook, Function: (...any) -> ...any)
		local DebugId = wax.shared.GetDebugId(Instance)

		if wax.shared.ShouldIgnore(Instance, getcallingscript()) or LogConnectionFunctions[Function] then
			return nil
		end

		local IncomingLogs = wax.shared.Logs.Incoming
		if not IncomingLogs then
			return nil
		end

		local Log = IncomingLogs[DebugId]
		if not Log then
			Log = wax.shared.NewLog(Instance, "Incoming", getcallingscript(), DebugId)
		end

		return Log
	end

	local function ResolveCallableFunction(Value: any): ((...any) -> ...any)?
		if typeof(Value) == "function" then
			return Value
		end

		local Success, Metatable = pcall(wax.shared.getrawmetatable, Value)
		if not Success or not Metatable then
			return nil
		end

		local HasCall, Call = pcall(rawget, Metatable, "__call")
		return if HasCall and typeof(Call) == "function" then Call else nil
	end

	
	local function LogRemote(
		Instance: InstancesToHook,
		Function: (...any) -> ...any,
		Info: {
			Arguments: { [number]: any, n: number },
			Origin: Instance,
			Function: (...any) -> ...any,
			Line: number,
			IsExecutor: boolean,
			Blocked: boolean?,
		}
	)
		local Log = GetLog(Instance, Function)
		if not Log then
			return false, nil
		end

		local ShouldBlock = Log:ShouldBlock(Info)
		local CallIndex = Log:Call(Info)
		return ShouldBlock, Log, CallIndex
	end

	
	local SupportsFilters = wax.shared.ExecutorSupport["FilterBase"].IsWorking

	
	local function CreateBaseFilter()
		local Filters = {}
		if not SupportsFilters then
			return Filters
		end

		
		for ClassName in ClassesToHook do
			table.insert(Filters, InstanceTypeFilter.new(1, ClassName))
		end

		return Filters
	end
	

	
	local function IsCobaltConnectionFunction(Function): boolean
		if not Function then
			return false
		end

		if LogConnectionFunctions[Function] then
			return true
		end

		local Success, Environment = pcall(getfenv, Function)
		local VerificationToken = wax.shared.CobaltVerificationToken
		return (
			Success
			and VerificationToken ~= nil
			and typeof(Environment) == "table"
			and rawequal(rawget(Environment, CobaltObserverEnvironmentKey), VerificationToken)
		)
	end

	
	local function CreateConnectionFunction(Instance: InstancesToHook, Method: MethodsToHook)
		local CachedConnectionInfo = nil
		local CachedConnectionCount = -1

		local DebugId = wax.shared.GetDebugId(Instance)

		local ConnectionFunction = function(...)
			
			local ExistingLog = wax.shared.Logs.Incoming[DebugId]
			if ExistingLog and ExistingLog.Ignored then
				return
			end

			local Signal = (Instance :: any)[Method]
			local Connections = getconnections(Signal)
			local ConnectionCount = #Connections

			
			if ConnectionCount ~= CachedConnectionCount then
				CachedConnectionCount = ConnectionCount

				local Information = {
					HasValidConnections = false,
					HasForeignLuaConnections = false,
					Entries = {},
				}

				for _, Connection in Connections do
					
					if Connection.ForeignState then
						
						if Connection.LuaConnection then
							Information.HasForeignLuaConnections = true
						end

						continue
					end

					
					local Function = typeof(Connection.Function) == "function" and (Connection.Function) or (nil)
					if IsCobaltConnectionFunction(Function) then
						continue
					end

					Information.HasValidConnections = true

					
					local Thread = Connection.Thread
					local Origin = nil

					if Thread and getscriptfromthread then
						Origin = getscriptfromthread(Thread)
					end

					if not Origin and Function then
						
						

						local Script = rawget(getfenv(Function), "script")
						if typeof(Script) == "Instance" then
							Origin = Script
						end
					end

					table.insert(Information.Entries, {
						Function = Function,
						Origin = Origin,
						IsExecutor = Function and isexecutorclosure(Function) or false,
					})
				end

				CachedConnectionInfo = Information
			end

			local Arguments = wax.shared.SafePack.Pack(...)
			local TargetLog, TargetCallIndex

			
			if CachedConnectionInfo.HasValidConnections then
				for _, Entry in CachedConnectionInfo.Entries do
					TargetLog, TargetCallIndex = select(2, LogRemote(Instance, Entry.Function, {
						Arguments = Arguments,
						Origin = Entry.Origin,
						Function = Entry.Function,
						Line = nil,
						IsExecutor = Entry.IsExecutor,
					}))
				end

			elseif not wax.shared.IS_ACTOR then
				TargetLog, TargetCallIndex = select(2, LogRemote(Instance, nil, {
					Arguments = Arguments,
					Origin = nil,
					Function = nil,
					Line = nil,
					IsExecutor = false,
				}))
			end

			local Communicator = wax.shared.ActorCommunicator
			if Communicator then
				if
					not wax.shared.IS_ACTOR
					and CachedConnectionInfo.HasForeignLuaConnections
					and TargetLog
					and TargetCallIndex
				then
					Communicator:Fire(
						"InspectIncomingConnections",
						Instance,
						Method,
						TargetLog.Index,
						TargetCallIndex
					)
				end
			end
		end

		local OriginalEnvironment = getfenv(ConnectionFunction)
		setfenv(ConnectionFunction, setmetatable({
			[CobaltObserverEnvironmentKey] = wax.shared.CobaltVerificationToken,
		}, {
			__index = OriginalEnvironment,
			__newindex = OriginalEnvironment,
		}))

		LogConnectionFunctions[ConnectionFunction] = true
		return ConnectionFunction
	end
	

	
	
	local function HandleCallbackLogging(Log, Info, InitialEnv, InitialIdentity, ...)
		setfenv(0, InitialEnv)
		setthreadidentity(InitialIdentity)

		if Log then
			Info.InvokeResult = wax.shared.SafePack.Pack(...)
			Log:Call(Info)
		end

		return ...
	end

	
	local function CreateCallbackDetour(Instance: InstancesToHook, Callback: any)
		local CallbackFunction = assert(ResolveCallableFunction(Callback), "Callback is not callable")
		local Detour = function(...)
			local Origin = nil

			
			if getscriptfromthread then
				Origin = getscriptfromthread(coroutine.running())
			end

			
			if not Origin then
				local Script = rawget(getfenv(CallbackFunction), "script")
				if typeof(Script) == "Instance" then
					Origin = Script
				end
			end

			local FunctionCaller = debug.info(2, "f")
			local IsExecutor = if typeof(FunctionCaller) == "function"
				then isexecutorclosure(FunctionCaller)
				else isexecutorclosure(CallbackFunction)

			local Arguments = wax.shared.SafePack.Pack(...)
			local Log = GetLog(Instance, CallbackFunction)
			local Info = {
				Arguments = Arguments,
				Origin = Origin,
				Function = CallbackFunction,
				Line = nil,
				IsExecutor = IsExecutor,
				InvokeKind = "Callback",
			}
			if Log and Log:ShouldBlock(Info) then
				Log:Call(Info)
				return
			end

			local InitialEnv, InitialIdentity = getfenv(CreateCallbackDetour), getthreadidentity()
			local IsDirectFunction = rawequal(Callback, CallbackFunction)

			setthreadidentity(2)
			setfenv(0, getfenv(CallbackFunction))
			if IsDirectFunction then
				return HandleCallbackLogging(
					Log,
					Info,
					InitialEnv,
					InitialIdentity,
					CallbackFunction(...)
				)
			end

			return HandleCallbackLogging(
				Log,
				Info,
				InitialEnv,
				InitialIdentity,
				CallbackFunction(Callback, ...)
			)
		end

		if wax.shared.ExecutorSupport["setstackhidden"].IsWorking then
			setstackhidden(Detour, true)
		end

		CallbackOwners[Detour] = {
			Original = Callback,
			Method = ClassesToHook[Instance.ClassName],
			Instance = Instance
		}
		return Detour
	end

	local function GetOriginalScript(OriginalEnv: { [string]: any}): Instance?
		local OriginalScript = rawget(OriginalEnv, "script")
		if typeof(OriginalScript) ~= "Instance" then
			return nil
		end

		return OriginalScript
	end

	
	wax.shared.RestoreCallbackDetours = function()
		for Detour, Owner in CallbackOwners do
			local Success, CurrentCallback = pcall(getcallbackvalue, Owner.Instance, Owner.Method)
			if not (Success and rawequal(CurrentCallback, Detour)) then
				continue
			end

			pcall(function()
				if wax.shared.trampoline_call then
					local OriginalEnv = getfenv(Owner.Original)
					local OriginalScript = GetOriginalScript(OriginalEnv)

					wax.shared.trampoline_call(function()
						Owner.Instance[Owner.Method] = Owner.Original
					end, {}, {
						env = OriginalEnv,
						script = OriginalScript,
						identity = 2
					})
				else
					task.spawn(function()
						local OriginalEnv = getfenv(Owner.Original)

						setthreadidentity(2)
						setfenv(0, OriginalEnv)
						Owner.Instance[Owner.Method] = Owner.Original
					end)
				end
			end)
		end

		table.clear(CallbackOwners)
	end

	

	
	local function HandleInstance(Instance: any)
		if
			not ClassesToHook[Instance.ClassName]
			or Instance == wax.shared.Communicator
			or Instance == wax.shared.ActorCommunicator
		then
			return
		end

		local Method = ClassesToHook[Instance.ClassName]

		if ConnectionsEnabled and not ObservedConnectionInstances[Instance] then
			if Instance.ClassName == "RemoteEvent" or Instance.ClassName == "UnreliableRemoteEvent" then
				wax.shared.Connect(Instance.OnClientEvent:Connect(CreateConnectionFunction(Instance, Method)))

				SignalMapping[Instance.OnClientEvent] = Instance
				ObservedConnectionInstances[Instance] = true
			elseif Instance.ClassName == "BindableEvent" then
				wax.shared.Connect(Instance.Event:Connect(CreateConnectionFunction(Instance, Method)))

				SignalMapping[Instance.Event] = Instance
				ObservedConnectionInstances[Instance] = true
			end
		end

		if CallbacksEnabled then
			if Instance.ClassName == "RemoteFunction" or Instance.ClassName == "BindableFunction" then
				local IsCoreRemote = Instance:IsDescendantOf(wax.shared.RobloxReplicatedStorage)
				if IsCoreRemote then return end

				local Success, Callback = pcall(getcallbackvalue, Instance, Method)
				local IsCallable = ResolveCallableFunction(Callback) ~= nil

				if not Success or not IsCallable or CallbackOwners[Callback] then
					return
				end

				
				if wax.shared.trampoline_call then
					local OriginalEnv = getfenv(Callback)
					local OriginalScript = GetOriginalScript(OriginalEnv)

					wax.shared.trampoline_call(function()
						Instance[Method] = CreateCallbackDetour(Instance, Callback)
					end, {}, {
						env = OriginalEnv,
						script = OriginalScript,
						identity = 2
					})
				else
					Instance[Method] = CreateCallbackDetour(Instance, Callback)
				end
			end
		end
	end

	
	local function SetupCallbackAssignmentHook()
		local NewIndexHookFilter = SupportsFilters and AnyFilter.new(CreateBaseFilter())
		
		wax.shared.NewIndexHook = wax.shared.Hooking.HookMetaMethod(game, "__newindex", function(...)
			local self, key, value = ...

			if typeof(self) ~= "Instance" or not ClassesToHook[self.ClassName] then
				return wax.shared.NewIndexHook(...)
			end

			if self.ClassName == "RemoteFunction" or self.ClassName == "BindableFunction" then
				local Method = ClassesToHook[self.ClassName]

				local IsCallable = ResolveCallableFunction(value) ~= nil

				if key == Method and IsCallable then
					if CallbackOwners[value] then
						return wax.shared.NewIndexHook(...)
					end

					return wax.shared.NewIndexHook(self, key, CreateCallbackDetour(self :: InstancesToHook, value))
				end
			end

			return wax.shared.NewIndexHook(...)
		end, NewIndexHookFilter)
	end

	
	local function HandleConnectionLogging(Instance, Method, callback, ...)
		local Log = wax.shared.Logs.Incoming[wax.shared.GetDebugId(Instance)]

		if Log and Log.Blocked then
			for _, Connection in getconnections(Instance[Method]) do
				if not Connection.ForeignState and Connection.Function ~= callback then
					continue
				end

				Connection:Disable()
			end
		end

		return ...
	end

	
	local function SetupConnectionAssignmentHook()
		local SignalMetatable = wax.shared.getrawmetatable(Instance.new("Part").Touched)
		wax.shared.Hooks[SignalMetatable.__index] = wax.shared.Hooking.HookFunction(SignalMetatable.__index, function(...)
			local self, key = ...

			if not wax.shared.Unloaded and ConnectionKeys[key] then
				local Instance = SignalMapping[self]
				local Connect = wax.shared.Hooks[SignalMetatable.__index](...)

				if not Instance then
					return Connect
				end

				local Method = ClassesToHook[Instance.ClassName]
				return wax.shared.newcclosure(function(...)
					local _self, callback = ...
					return HandleConnectionLogging(Instance, Method, callback, Connect(...))
				end, debug.info(Connect, "n"))
			end

			return wax.shared.Hooks[SignalMetatable.__index](...)
		end)
	end

	local Started = false
	wax.shared.IncomingInterceptor = function(Options: Options?)
		if Started then
			return
		end

		
		Options = Options or {}
		do
			ConnectionsEnabled = Options.Connections ~= false
			CallbacksEnabled = Options.Callbacks ~= false
			ConnectionHookEnabled = Options.HookConnections ~= false
		end

		if not ConnectionsEnabled and not CallbacksEnabled then
			return
		end

		Started = true

		
		if CallbacksEnabled then
			if wax.shared.ExecutorSupport["setstackhidden"].IsWorking then
				setstackhidden(HandleCallbackLogging, true)
			end

			SetupCallbackAssignmentHook()
		end

		if ConnectionsEnabled and ConnectionHookEnabled then
			SetupConnectionAssignmentHook()
		end

		wax.shared.Connect(game.DescendantAdded:Connect(function(instance)
			HandleInstance(cloneref(instance))
		end))

		
		local ClassesToSearch = {}
		do
			if ConnectionsEnabled then
				table.insert(ClassesToSearch, "RemoteEvent")
				table.insert(ClassesToSearch, "UnreliableRemoteEvent")
				table.insert(ClassesToSearch, "BindableEvent")
			end
			if CallbacksEnabled then
				table.insert(ClassesToSearch, "RemoteFunction")
				table.insert(ClassesToSearch, "BindableFunction")
			end
		end

		local Categories = {
			game:QueryDescendants(table.concat(ClassesToSearch, ", ")),
		}
		if wax.shared.ExecutorSupport["getnilinstances"].IsWorking then
			table.insert(Categories, getnilinstances())
		end

		for _, Category in Categories do
			for _, TargetInstance in next, Category do
				HandleInstance(cloneref(TargetInstance))
			end
		end
	end
end


task.spawn(wax.shared.IncomingInterceptor, {
	Connections = false,
	Callbacks = Data.IncomingCallbacks,
	HookConnections = false,
})

if Data.Outgoing then
	task.spawn(function()
		local function CreateLookupTable(table)
			local LookupTable = {}
			for _, Method in next, table do
				LookupTable[Method] = true
			end
			return LookupTable
		end

		local NamecallMethods = {
			["FireServer"] = CreateLookupTable({"RemoteEvent", "UnreliableRemoteEvent"}),
			["fireServer"] = CreateLookupTable({"RemoteEvent", "UnreliableRemoteEvent"}),
			
			["InvokeServer"] = CreateLookupTable({"RemoteFunction"}),
			["invokeServer"] = CreateLookupTable({"RemoteFunction"}),

			["Fire"] = CreateLookupTable({"BindableEvent"}),
			["fire"] = CreateLookupTable({"BindableEvent"}),
			
			["Invoke"] = CreateLookupTable({"BindableFunction"}),
			["invoke"] = CreateLookupTable({"BindableFunction"}),
		}
		local AllowedClassNames =
			CreateLookupTable({ "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BindableEvent", "BindableFunction" })

		
		local function getcallingfunction()
			local BaseLevel = if wax.shared.IsUsingOthHooks then 3 else 5

			for i = BaseLevel, 10 do
				local Function, Source = debug.info(i, "fs")
				if not Function or not Source then
					break
				end

				if Source == "[C]" then
					continue
				end

				return Function
			end

			return debug.info(BaseLevel, "f")
		end

		
		local function getcallingline()
			local BaseLevel = if wax.shared.IsUsingOthHooks then 3 else 5

			for i = BaseLevel, 10 do
				local Source, Line = debug.info(i, "sl")
				if not Source then
					break
				end

				if Source == "[C]" then
					continue
				end

				return Line
			end

			return debug.info(BaseLevel, "l")
		end

		
		local function getcallingsource()
			local BaseLevel = if wax.shared.IsUsingOthHooks then 3 else 5

			for i = BaseLevel, 10 do
				local Source = debug.info(i, "s")
				if not Source then
					break
				end

				if Source == "[C]" then
					continue
				end

				return Source
			end

			return debug.info(BaseLevel, "s")
		end

		
		local function GetLog(Instance: Instance, Direction: "Outgoing" | "Incoming")
			local DebugId = wax.shared.GetDebugId(Instance)

			local LogsInDirection = wax.shared.Logs[Direction]
			if not LogsInDirection then
				return nil
			end

			local Log = LogsInDirection[DebugId]
			if not Log then
				Log = wax.shared.NewLog(Instance, Direction, getcallingscript(), DebugId)
			end

			return Log
		end

		
		local function HandleLoggingResult(Log, Info, ResultKey, ...)
			local Result = wax.shared.SafePack.Pack(...)
			Info[ResultKey] = Result
			Log:Call(Info)

			return ...
		end

		
		local function HandleLogging(TargetInstance: Instance, Method: string, OldFunction: (...any) -> ...any, ...)
			local Log = GetLog(TargetInstance, "Outgoing")
			if not Log then
				return OldFunction(...)
			end
			local Arguments = wax.shared.SafePack.Pack(select(2, ...))

			local Info = {
				Arguments = Arguments,
				Origin = getcallingscript(),
				Function = getcallingfunction(),
				Line = getcallingline(),
				Source = getcallingsource(),
				IsExecutor = checkcaller(),
			}
			local ShouldBlock = Log:ShouldBlock(Info)
			Log:Call(Info)
			if ShouldBlock then
				return
			end

			local IsRemoteFunctionInvoke = (
				TargetInstance.ClassName == "RemoteFunction" and (Method == "InvokeServer" or Method == "invokeServer")
			)

			local IsBindableFunctionInvoke = (
				TargetInstance.ClassName == "BindableFunction" and (Method == "Invoke" or Method == "invoke")
			)

			if IsRemoteFunctionInvoke or IsBindableFunctionInvoke then
				
				Log = GetLog(TargetInstance, "Incoming")
				local RFResultInfo = {
					Arguments = Arguments,
					InvokeResult = nil,
					Origin = getcallingscript(),
					Function = getcallingfunction(),
					Line = getcallingline(),
					Source = getcallingsource(),
					IsExecutor = checkcaller(),
					InvokeKind = "Request",
				}

				if Log:ShouldBlock(RFResultInfo) then
					Log:Call(RFResultInfo)
					return
				end

				return HandleLoggingResult(Log, RFResultInfo, "InvokeResult", OldFunction(...))
			end

			return OldFunction(...)
		end

		
		local SupportsFilters = wax.shared.ExecutorSupport["FilterBase"].IsWorking

		
		local function CreateBaseFilter()
			local Filters = {}
			if not SupportsFilters then
				return Filters
			end

			
			table.insert(Filters, NotFilter.new(ArgumentFilter.new(1, wax.shared.Communicator)))
			table.insert(Filters, NotFilter.new(ArgumentFilter.new(1, wax.shared.ActorCommunicator)))

			return Filters
		end

		local NamecallHookFilter = SupportsFilters and AllFilter.new((function()
			local Filters = CreateBaseFilter()

			

			
			local AnyClassNameFilters = {}
			for ClassName in AllowedClassNames do
				table.insert(AnyClassNameFilters, InstanceTypeFilter.new(1, ClassName))
			end
			
			
			local AnyNamecallMethoFilters = {}
		    for Method in NamecallMethods do
		        table.insert(AnyNamecallMethoFilters, NamecallFilter.new(Method))
		    end

			table.insert(Filters, AnyFilter.new(AnyClassNameFilters))
			table.insert(Filters, AnyFilter.new(AnyNamecallMethoFilters))
		    return Filters
		end)())
		

		
		wax.shared.NamecallHook = wax.shared.Hooking.HookMetaMethod(game, "__namecall", function(...)
			local self = ...
			local Method = getnamecallmethod()

			if
				typeof(self) == "Instance"
				and AllowedClassNames[self.ClassName]
				and not rawequal(self, wax.shared.Communicator)
				and not rawequal(self, wax.shared.ActorCommunicator)
				and (NamecallMethods[Method] and NamecallMethods[Method][self.ClassName])
				and not wax.shared.ShouldIgnore(self, getcallingscript())
			then
				return HandleLogging(cloneref(self), Method, wax.shared.NamecallHook, ...)
			end

			return wax.shared.NamecallHook(...)
		end, NamecallHookFilter)

		
		local FunctionsToHook
		do
			local BindableFunction = Instance.new("BindableFunction")
			local BindableEvent = Instance.new("BindableEvent")

			local RemoteFunction = Instance.new("RemoteFunction")
			local RemoteEvent = Instance.new("RemoteEvent")
			local UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")

			FunctionsToHook = {
				BindableFunction.Invoke,
				BindableEvent.Fire,

				RemoteFunction.InvokeServer,
				RemoteEvent.FireServer,
				UnreliableRemoteEvent.FireServer,
			}

			BindableFunction:Destroy()
			BindableEvent:Destroy()

			RemoteFunction:Destroy()
			RemoteEvent:Destroy()
			UnreliableRemoteEvent:Destroy()
		end

		local FunctionHookFilter = SupportsFilters and AllFilter.new((function()
			local Filters = CreateBaseFilter()

			

			local ClassFilters = {}
			for ClassName in AllowedClassNames do
				table.insert(ClassFilters, InstanceTypeFilter.new(1, ClassName))
			end

			table.insert(Filters, AnyFilter.new(ClassFilters))
			return Filters
		end)())

		for _, Function in next, FunctionsToHook do
			local Method = debug.info(Function, "n")

			wax.shared.Hooks[Function] = wax.shared.Hooking.HookFunction(Function, function(...)
				local self = ...

				if
					typeof(self) == "Instance"
					and AllowedClassNames[self.ClassName]
					and not rawequal(self, wax.shared.Communicator)
					and not wax.shared.ShouldIgnore(self, getcallingscript())
				then
					return HandleLogging(cloneref(self), Method, wax.shared.Hooks[Function], ...)
				end

				return wax.shared.Hooks[Function](...)
			end, FunctionHookFilter)
		end
	end)
end

task.spawn(function()
	local getrawmetatable = getrawmetatable or debug.getmetatable

	wax.shared.Communicator.Event:Connect(function(Type, ...)
		if Type ~= "Unload" then
			return
		end

		local gameMetatable = getrawmetatable(game)

		if wax.shared.ExecutorSupport["oth"].IsWorking then
			if Data.Outgoing then
				pcall(oth.unhook, gameMetatable.__namecall)
			end
			if Data.IncomingCallbacks then
				pcall(oth.unhook, gameMetatable.__newindex)
			end
		else
			if wax.shared.ExecutorSupport["restorefunction"].IsWorking and wax.shared.ExecutorSupport["hookmetamethod"].IsWorking then
				if Data.Outgoing then
					pcall(restorefunction, gameMetatable.__namecall)
				end
				if Data.IncomingCallbacks then
					pcall(restorefunction, gameMetatable.__newindex)
				end
			else
				if Data.Outgoing then
					wax.shared.Hooking.HookMetaMethod(game, "__namecall", wax.shared.NamecallHook)
				end
				if Data.IncomingCallbacks then
					wax.shared.Hooking.HookMetaMethod(game, "__newindex", wax.shared.NewIndexHook)
				end
				end
			end

			if Data.IncomingCallbacks and wax.shared.RestoreCallbackDetours then
				wax.shared.RestoreCallbackDetours()
			end

			for Function, Original in pairs(wax.shared.Hooks) do
			if wax.shared.ExecutorSupport["oth"].IsWorking then
				task.spawn(pcall, oth.unhook, Function)
			elseif wax.shared.ExecutorSupport["restorefunction"].IsWorking then
				task.spawn(pcall, wax.shared.restorefunction, Function)
			else
				pcall(wax.shared.Hooking.HookFunction, Function, Original)
			end
		end

		task.defer(function()
			getgenv().CobaltInitialized = false
		end)
	end)
end)
