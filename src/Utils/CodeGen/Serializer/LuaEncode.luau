-- LuaEncode - Fast table serialization library for pure Luau/Lua 5.1+
-- MIT License | Copyright (c) 2022-2025 Chad Hyatt <chad@hyatt.page>
-- https://github.com/chadhyatt/LuaEncode








local table, string, next, pcall, game, workspace, tostring, tonumber, getmetatable =
    table, string, next, pcall, game, workspace, tostring, tonumber, getmetatable

local SerializeInstance = require(script.Parent.Instance).Serialize

local string_pack = string.pack
local string_byte = string.byte
local string_format = string.format
local string_char = string.char
local string_gsub = string.gsub
local string_match = string.match
local string_rep = string.rep
local string_sub = string.sub
local string_gmatch = string.gmatch

local table_concat = table.concat

local Type = typeof or type

local function LookupTable(array, lookupType)
    local Out = {}

    if lookupType == "key" then
        for Key, _ in next, array do
            Out[Key] = true
        end
    else
        for _, Value in next, array do
            Out[Value] = true
        end
    end

    return Out
end



local LuaKeywords = LookupTable({
    "and",
    "break",
    "do",
    "else",
    "elseif",
    "end",
    "false",
    "for",
    "function",
    "if",
    "in",
    "local",
    "nil",
    "not",
    "or",
    "repeat",
    "return",
    "then",
    "true",
    "until",
    "while",
    "continue",
})


local NumberCorrection = {
    [string_pack(">n", 0 / 0)] = "0/0",
    [string_pack(">n", -(0 / 0))] = "-(0/0)",
    [string_pack(">n", tonumber("nan"))] = 'tonumber("nan")',
    [string_pack(">n", tonumber("-nan"))] = 'tonumber("-nan")',
}


local KeyIndexTypes = LookupTable({
    "number",
    "string",
    "boolean",
    "Enum",
    "EnumItem",
    "Enums",
})

local DirectIndexPat = "^[A-Za-z_][A-Za-z0-9_]*$"

local function CheckType(inputData, dataName, ...)
    local ValidTypes = { ... }
    local ValidTypesLookup = LookupTable(ValidTypes)
    local InputType = Type(inputData)

    if not ValidTypesLookup[InputType] then
        error(
            string_format(
                "LuaEncode: Incorrect type for `%s`: `%s` expected, got `%s`",
                dataName,
                table_concat(ValidTypes, ", "), 
                InputType
            ),
            0
        )
    end

    return inputData
end



local SerializeString
do
    
    local SpecialCharacters = {
        ['"'] = '\\"',
        ["\\"] = "\\\\",
        ["\a"] = "\\a",
        ["\b"] = "\\b",
        ["\t"] = "\\t",
        ["\n"] = "\\n",
        ["\v"] = "\\v",
        ["\f"] = "\\f",
        ["\r"] = "\\r",
    }

    for Index = 0, 255 do
        local Character = string_char(Index)

        if not SpecialCharacters[Character] and (Index < 32 or Index > 126) then
            SpecialCharacters[Character] = string_format("\\x%02X", Index)
        end
    end

    function SerializeString(inputString)
        
        
        return table_concat({ '"', string_gsub(inputString, '[%z\\"\1-\31\127-\255]', SpecialCharacters), '"' })
    end
end


local function CommentBlock(inputString)
    local Longest = -1
    for Match in string_gmatch(inputString, "%](=*)%]") do
        if #Match > Longest then
            Longest = #Match
        end
    end

    local Padding = string_rep("=", Longest + 1)
    return "--[" .. Padding .. "[" .. inputString .. "]" .. Padding .. "]"
end



local function LuaEncode(inputTable, options)
    options = options or {}

    CheckType(inputTable, "inputTable", "table")
    CheckType(options, "options", "table")

    CheckType(options.Prettify, "options.Prettify", "boolean", "nil")
    CheckType(options.PrettyPrinting, "options.PrettyPrinting", "boolean", "nil") 
    CheckType(options.IndentCount, "options.IndentCount", "number", "nil")
    CheckType(options.InsertCycles, "options.InsertCycles", "boolean", "nil")
    CheckType(options.OutputWarnings, "options.OutputWarnings", "boolean", "nil")
    CheckType(options.FunctionsReturnRaw, "options.FunctionsReturnRaw", "boolean", "nil")
    CheckType(options.UseInstancePaths, "options.UseInstancePaths", "boolean", "nil")
    CheckType(options.UseFindFirstChild, "options.UseFindFirstChild", "boolean", "nil")
    CheckType(options.SerializeMathHuge, "options.SerializeMathHuge", "boolean", "nil")
    CheckType(options.DisableNilParentHandler, "options.DisableNilParentHandler", "boolean", "nil")
    CheckType(options.IsArray, "options.IsArray", "boolean", "nil")

    CheckType(options._StackLevel, "options._StackLevel", "number", "nil")
    CheckType(options._VisitedTables, "options._VisitedTables", "table", "nil")
    CheckType(options._SharedTableLarpAsRegTable, "options._SharedTableLarpAsRegTable", "boolean", "nil")

    local Prettify = (options.Prettify == nil and options.PrettyPrinting == nil and false)
        or (options.Prettify ~= nil and options.Prettify)
        or (options.PrettyPrinting and options.PrettyPrinting)
    local IndentCount = options.IndentCount or (Prettify and 4) or 0
    local InsertCycles = (options.InsertCycles == nil and false) or options.InsertCycles
    local OutputWarnings = (options.OutputWarnings == nil and true) or options.OutputWarnings
    local UseInstancePaths = (options.UseInstancePaths == nil and true) or options.UseInstancePaths
    local DisableNilParentHandler = options.DisableNilParentHandler or false
    local SerializeMathHuge = (options.SerializeMathHuge == nil and true) or options.SerializeMathHuge
    local IsArray = (options.IsArray == nil and false) or options.IsArray

    local StackLevelOpt = options._StackLevel or 1
    local VisitedTables = options._VisitedTables or {} 
    local SharedTableLarpAsRegTable = options._SharedTableLarpAsRegTable or false
    local DidInsertNilFunction = options._DidInsertNilFunction or false

    
    local PositiveInf = (SerializeMathHuge and "math.huge") or "1/0"
    local NegativeInf = (SerializeMathHuge and "-math.huge") or "-1/0"
    local NewEntryString = (Prettify and "\n") or ""
    local CodegenNewline = (Prettify and "\n") or " "
    local ValueSeperator = (Prettify and ", ") or ","
    local BlankSeperator = (Prettify and " ") or ""
    local EqualsSeperator = (Prettify and " = ") or "="

    local StackLevel = StackLevelOpt

    
    local IndentStringBase = string_rep(" ", IndentCount)

    
    local IndentString = nil
    local EndingIndentString = nil

    
    

    
    local KeyNumIndex = 1

    
    local TypeCases = {}
    do
        local function TypeCase(typeName, value, ...)
            local EncodedValue = TypeCases[typeName](value, false, ...) 
            return EncodedValue
        end

        local function Args(...)
            local EncodedValues = {}

            for _, Arg in next, { ... } do
                EncodedValues[#EncodedValues + 1] = TypeCase(Type(Arg), Arg)
            end

            return table_concat(EncodedValues, ValueSeperator)
        end

        
        local function Params(newData, params)
            return "(function(p, t) for n, v in next, t do p[n] = v end return p end)("
                .. table_concat({ newData, TypeCase("table", params) }, ValueSeperator)
                .. ")"
        end

        TypeCases["number"] = function(value, isKey)
            
            
            if isKey and value == KeyNumIndex then
                
                KeyNumIndex = KeyNumIndex + 1
                return nil, true
            end

            
            
            if value == 1 / 0 then
                return PositiveInf
            elseif value == -1 / 0 then
                return NegativeInf
            elseif value == math.pi then
                return "math.pi"
            end

            
            local NumberPacked = string_pack(">n", value) 
            local CorrectedNumber = NumberCorrection[NumberPacked]
            if CorrectedNumber then
                return CorrectedNumber
            end

            if value ~= value then
                return string_format(
                    '(string.unpack(">n", "\\%*\\%*\\%*\\%*\\%*\\%*\\%*\\%*"))',
                    string_byte(NumberPacked, 1, 8)
                )
            end

            
            return string_format("%.14g", value)
        end

        TypeCases["string"] = function(value, isKey)
            if isKey and not LuaKeywords[value] and string_match(value, DirectIndexPat) then
                
                return value, true
            end

            return SerializeString(value)
        end

        
        
        TypeCases["table"] = function(value, isKey, stLarpAsRegTable)
            
            if VisitedTables[value] and OutputWarnings then
                return "{--[[LuaEncode: Duplicate reference]]}"
            end

            local NewOptions = setmetatable({}, { __index = options })
            do
                NewOptions.Prettify = (isKey and false) or Prettify
                NewOptions.IndentCount = (isKey and ((not Prettify and IndentCount) or 1)) or IndentCount
                NewOptions._StackLevel = (isKey and 1) or StackLevel + 1
                NewOptions._VisitedTables = VisitedTables
                NewOptions._SharedTableLarpAsRegTable = (not isKey and stLarpAsRegTable)
                NewOptions.IsArray = false
                NewOptions._DidInsertNilFunction = DidInsertNilFunction
            end

            local Result, DidInsertNilFunction = LuaEncode(value, NewOptions)
            if DidInsertNilFunction then
                DidInsertNilFunction = true
            end

            return Result
        end

        TypeCases["boolean"] = function(value)
            return value and "true" or "false"
        end

        TypeCases["nil"] = function(value)
            return "nil"
        end

        TypeCases["thread"] = function(value)
            return "task.spawn(function() end)"
        end

        TypeCases["function"] = function(value)
            
            local FunctionName, ArgumentCount, VarArg, Line = debug.info(value, "nal")

            local Arguments = {}
            for Index = 1, ArgumentCount do
                Arguments[Index] = string_format("arg%d", Index)
            end

            local BodyIndent = IndentString .. IndentStringBase
            local Details = {
                `Name: {FunctionName == "" and "Anonymous Function" or FunctionName} | Line: {Line}`,
                if islclosure(value)
                    then `Upvalues: {#debug.getupvalues(value)}`
                    else "Upvalues: N/A (C Closure)",
                if getfunctionhash
                    then if islclosure(value)
                        then `Function Hash: {getfunctionhash(value)}`
                        else "Function Hash: N/A (C Closure)"
                    else "Function Hash: N/A (getfunctionhash == nil)",
            }
            if OutputWarnings then
                Details[#Details + 1] = "LuaEncode: Unable to serialize function"
            end

            return string_format(
                [[function(%s)%sreturn%send]],
                `{table_concat(Arguments, ", ")}{VarArg and `{Arguments[1] and ", " or ""}...` or ""}`,
                `{CodegenNewline}{BodyIndent}{CommentBlock(table_concat(Details, CodegenNewline .. BodyIndent))}{CodegenNewline}{BodyIndent}`,
                `{CodegenNewline}{IndentString}`
            )
        end

        

        TypeCases["Axes"] = function(value)
            local EncodedArgs = {}
            local EnumValues = {
                ["Enum.Axis.X"] = value.X,
                ["Enum.Axis.Y"] = value.Y,
                ["Enum.Axis.Z"] = value.Z,
            }

            for EnumValue, IsEnabled in next, EnumValues do
                if IsEnabled then
                    EncodedArgs[#EncodedArgs + 1] = EnumValue
                end
            end

            return "Axes.new(" .. table_concat(EncodedArgs, ValueSeperator) .. ")"
        end

        TypeCases["BrickColor"] = function(value)
            
            
            return "BrickColor.new(" .. ((Prettify and TypeCase("string", value.Name)) or value.Number) .. ")"
        end

        TypeCases["CFrame"] = function(value)
            return "CFrame.new(" .. Args(value:components()) .. ")"
        end

        TypeCases["CatalogSearchParams"] = function(value)
            return Params("CatalogSearchParams.new()", {
                SearchKeyword = value.SearchKeyword,
                MinPrice = value.MinPrice,
                MaxPrice = value.MaxPrice,
                SortType = value.SortType, 
                CategoryFilter = value.CategoryFilter, 
                BundleTypes = value.BundleTypes, 
                AssetTypes = value.AssetTypes, 
            })
        end

        TypeCases["Color3"] = function(value)
            return "Color3.new(" .. Args(value.R, value.G, value.B) .. ")"
        end

        TypeCases["ColorSequence"] = function(value)
            return "ColorSequence.new(" .. TypeCase("table", value.Keypoints) .. ")"
        end

        TypeCases["ColorSequenceKeypoint"] = function(value)
            return "ColorSequenceKeypoint.new(" .. Args(value.Time, value.Value) .. ")"
        end

        TypeCases["DateTime"] = function(value)
            return "DateTime.fromUnixTimestamp(" .. value.UnixTimestamp .. ")"
        end

        
        
        TypeCases["DockWidgetPluginGuiInfo"] = function(value)
            
            local ValueString = tostring(value)

            return "DockWidgetPluginGuiInfo.new("
                .. Args(
                    
                    Enum.InitialDockState[string_match(ValueString, "InitialDockState:(%w+)")], 
                    
                    string_match(ValueString, "InitialEnabled:(%w+)") == "1", 
                    string_match(ValueString, "InitialEnabledShouldOverrideRestore:(%w+)") == "1", 
                    
                    tonumber(string_match(ValueString, "FloatingXSize:(%w+)")), 
                    tonumber(string_match(ValueString, "FloatingYSize:(%w+)")), 
                    
                    tonumber(string_match(ValueString, "MinWidth:(%w+)")), 
                    tonumber(string_match(ValueString, "MinHeight:(%w+)")) 
                )
                .. ")"
        end

        
        TypeCases["Enum"] = function(value)
            local ValueString = tostring(value)

            if string_match(ValueString, DirectIndexPat) then
                return "Enum." .. ValueString
            end
            return "Enum[" .. SerializeString(ValueString) .. "]"
        end

        
        TypeCases["EnumItem"] = function(value)
            local EnumTypeStr = TypeCase("Enum", value.EnumType)
            local EnumName = value.Name

            if string_match(EnumName, DirectIndexPat) then
                return EnumTypeStr .. "." .. value.Name
            end
            return EnumTypeStr .. "[" .. SerializeString(EnumName) .. "]"
        end

        
        TypeCases["Enums"] = function(value)
            return "Enum"
        end

        TypeCases["Faces"] = function(value)
            local EncodedArgs = {}
            local EnumValues = {
                ["Enum.NormalId.Top"] = value.Top, 
                ["Enum.NormalId.Bottom"] = value.Bottom,
                ["Enum.NormalId.Left"] = value.Left,
                ["Enum.NormalId.Right"] = value.Right,
                ["Enum.NormalId.Back"] = value.Back,
                ["Enum.NormalId.Front"] = value.Front,
            }

            for EnumValue, IsEnabled in next, EnumValues do
                if IsEnabled then
                    EncodedArgs[#EncodedArgs + 1] = EnumValue
                end
            end

            return "Faces.new(" .. table_concat(EncodedArgs, ValueSeperator) .. ")"
        end

        TypeCases["FloatCurveKey"] = function(value)
            return "FloatCurveKey.new(" .. Args(value.Time, value.Value, value.Interpolation) .. ")"
        end

        TypeCases["Font"] = function(value)
            return "Font.new(" .. Args(value.Family, value.Weight, value.Style) .. ")"
        end

        TypeCases["Content"] = function(value)
            local source = value.SourceType

            if source == Enum.ContentSourceType.None then
                return "Content.none"
            elseif source == Enum.ContentSourceType.Uri then
                local uri = value.Uri or ""
                local assetId = string.match(uri, "^rbxassetid://(%d+)$")
                if assetId then
                    return "Content.fromAssetId(" .. assetId .. ")"
                end
                return "Content.fromUri(" .. TypeCase("string", uri) .. ")"
            elseif source == Enum.ContentSourceType.Object and value.Object then
                return "Content.fromObject(" .. TypeCase("Instance", value.Object) .. ")"
            end

            return "Content.none" .. BlankSeperator .. CommentBlock("Content source=" .. tostring(source))
        end

        
        
        TypeCases["Instance"] = function(value)
            if UseInstancePaths then
                local InstancePath, NilFunctionInserted = SerializeInstance(value, {
                    DisableNilParentHandler = DisableNilParentHandler,
                    OmitNilFunctionGetterCodeGeneration = true,
                })

                if NilFunctionInserted then
                    DidInsertNilFunction = true
                end

                if InstancePath then
                    return InstancePath
                end

                
            end

            return "nil"
                .. BlankSeperator
                .. CommentBlock("Instance.new(" .. TypeCase("string", value.ClassName) .. ")")
        end

        TypeCases["NumberRange"] = function(value)
            return "NumberRange.new(" .. Args(value.Min, value.Max) .. ")"
        end

        TypeCases["NumberSequence"] = function(value)
            return "NumberSequence.new(" .. TypeCase("table", value.Keypoints) .. ")"
        end

        TypeCases["NumberSequenceKeypoint"] = function(value)
            return "NumberSequenceKeypoint.new(" .. Args(value.Time, value.Value, value.Envelope) .. ")"
        end

        TypeCases["OverlapParams"] = function(value)
            return Params("OverlapParams.new()", {
                FilterDescendantsInstances = value.FilterDescendantsInstances,
                FilterType = value.FilterType,
                MaxParts = value.MaxParts,
                CollisionGroup = value.CollisionGroup,
                RespectCanCollide = value.RespectCanCollide,
            })
        end

        TypeCases["Path2DControlPoint"] = function(value)
            return "Path2DControlPoint.new(" .. Args(value.Position, value.LeftTangent, value.RightTangent) .. ")"
        end

        TypeCases["PathWaypoint"] = function(value)
            return "PathWaypoint.new(" .. Args(value.Position, value.Action, value.Label) .. ")"
        end

        TypeCases["PhysicalProperties"] = function(value)
            return "PhysicalProperties.new("
                .. Args(
                    value.Density,
                    value.Friction,
                    value.Elasticity,
                    value.FrictionWeight,
                    value.ElasticityWeight,
                    value.AcousticAbsorption
                )
                .. ")"
        end

        TypeCases["Random"] = function()
            return "Random.new()"
        end

        TypeCases["Ray"] = function(value)
            return "Ray.new(" .. Args(value.Origin, value.Direction) .. ")"
        end

        TypeCases["SecurityCapabilities"] = function(value)
            local caps = {}
            for _, item in Enum.SecurityCapability:GetEnumItems() do
                local IsAlias = table.find({ "AssetRequire", "Avatar" }, item.Name) ~= nil
                if IsAlias then
                    continue
                end

                if value:Contains(item) then
                    table.insert(caps, item)
                end
            end

            if #caps == 0 then
                return "SecurityCapabilities.new()"
            end

            return "SecurityCapabilities.new(" .. Args(table.unpack(caps)) .. ")"
        end

        TypeCases["RaycastParams"] = function(value)
            return Params("RaycastParams.new()", {
                FilterDescendantsInstances = value.FilterDescendantsInstances,
                FilterType = value.FilterType,
                IgnoreWater = value.IgnoreWater,
                CollisionGroup = value.CollisionGroup,
                RespectCanCollide = value.RespectCanCollide,
            })
        end

        TypeCases["Rect"] = function(value)
            return "Rect.new(" .. Args(value.Min, value.Max) .. ")"
        end

        
        TypeCases["Region3"] = function(value)
            local ValuePos = value.CFrame.Position
            local ValueSize = 0.5 * value.Size

            return "Region3.new("
                .. Args(
                    ValuePos - ValueSize, 
                    ValuePos + ValueSize 
                )
                .. ")"
        end

        TypeCases["Region3int16"] = function(value)
            return "Region3int16.new(" .. Args(value.Min, value.Max) .. ")"
        end

        TypeCases["TweenInfo"] = function(value)
            return "TweenInfo.new("
                .. Args(
                    value.Time,
                    value.EasingStyle,
                    value.EasingDirection,
                    value.RepeatCount,
                    value.Reverses,
                    value.DelayTime
                )
                .. ")"
        end

        TypeCases["RotationCurveKey"] = function(value)
            return "RotationCurveKey.new(" .. Args(value.Time, value.Value, value.Interpolation) .. ")"
        end

        TypeCases["UDim"] = function(value)
            return "UDim.new(" .. Args(value.Scale, value.Offset) .. ")"
        end

        TypeCases["UDim2"] = function(value)
            return "UDim2.new(" .. Args(value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset) .. ")"
        end

        TypeCases["Vector2"] = function(value)
            return "Vector2.new(" .. Args(value.X, value.Y) .. ")"
        end

        TypeCases["Vector2int16"] = function(value)
            return "Vector2int16.new(" .. Args(value.X, value.Y) .. ")"
        end

        TypeCases["Vector3"] = function(value)
            return "Vector3.new(" .. Args(value.X, value.Y, value.Z) .. ")"
        end

        TypeCases["Vector3int16"] = function(value)
            return "Vector3int16.new(" .. Args(value.X, value.Y, value.Z) .. ")"
        end

        TypeCases["buffer"] = function(value)
            if wax.shared.SaveManager:GetState("PreferBufferFromString") then
                return "buffer.fromstring(" .. SerializeString(buffer.tostring(value)) .. ")"
            end

            local Bytes = {}
            for i = 1, buffer.len(value) do
                table.insert(Bytes, buffer.readu8(value, i - 1))
            end

            return table_concat({
                "(function(bytes) ",
                CommentBlock("Type: buffer"),
                NewEntryString,
                IndentString,
                IndentStringBase,
                "local b = buffer.create(#bytes)",
                NewEntryString,
                IndentString,
                IndentStringBase,
                "for i = 1, #bytes do",
                NewEntryString,
                IndentString,
                IndentStringBase,
                IndentStringBase,
                "buffer.writeu8(b, i - 1, bytes[i])",
                NewEntryString,
                IndentString,
                IndentStringBase,
                "end",
                NewEntryString,
                IndentStringBase,
                IndentString,
                "return b",
                NewEntryString,
                IndentString,
                "end)({ ",
                table_concat(Bytes, ", "),
                " })",
            })
        end

        TypeCases["SharedTable"] = function(value, isKey)
            local StClone = {}
            
            
            for Key, Value in SharedTable.clone(value, not SharedTableLarpAsRegTable) do
                StClone[Key] = Value
            end

            local StCloneStr = TypeCases["table"](StClone, isKey, true) 
            if SharedTableLarpAsRegTable then
                return StCloneStr
            end
            return table_concat({ "SharedTable.new(", StCloneStr, ")" })
        end

        TypeCases["userdata"] = function(value)
            if getmetatable(value) ~= nil then 
                return "newproxy(true)"
            else
                return "newproxy()" 
            end
        end
    end

    
    local Output = {}

    local TablePointer = inputTable
    local NextKey = nil 
    local IsNewTable = true 

    
    local TableStack = {} 
    local RefMaps = { [TablePointer] = "" } 
    local CycleMaps = {} 

    if IsArray then
        NextKey = 1
    end

    while TablePointer do
        
        StackLevel = StackLevelOpt + #TableStack
        IndentString = (Prettify and string_rep(IndentStringBase, StackLevel)) or IndentStringBase
        EndingIndentString = (#IndentString > 0 and string_sub(IndentString, 1, -IndentCount - 1)) or ""

        local HasNextValue = (IsArray and NextKey < TablePointer["n"])
            or (not IsArray and next(TablePointer, NextKey) ~= nil)

        
        if IsNewTable then
            Output[#Output + 1] = "{"
        elseif not HasNextValue then 
            Output[#Output + 1] = NewEntryString .. EndingIndentString
        else
            Output[#Output + 1] = ","
        end

        VisitedTables[TablePointer] = true

        
        local SkipStackPop = false

        local function WalkTable(Key, Value)
            local KeyType, ValueType = Type(Key), Type(Value)
            local ValueIsTable = ValueType == "table"
            local KeyTypeCase, ValueTypeCase = TypeCases[KeyType], TypeCases[ValueType]

            Output[#Output + 1] = NewEntryString .. IndentString

            if KeyTypeCase and ValueTypeCase then
                local ValueWasEncoded = false 

                
                local KeyEncodedSuccess, EncodedKeyOrError, DontEncloseKeyInBrackets = pcall(KeyTypeCase, Key, true) 

                
                local ValueEncodedSuccess, EncodedValueOrError
                if not ValueIsTable then
                    ValueEncodedSuccess, EncodedValueOrError = pcall(ValueTypeCase, Value, false)
                end

                
                
                if KeyEncodedSuccess and (ValueIsTable or (ValueEncodedSuccess and EncodedValueOrError)) then
                    
                    if EncodedKeyOrError then
                        if DontEncloseKeyInBrackets then
                            Output[#Output + 1] = EncodedKeyOrError
                        else
                            Output[#Output + 1] = table_concat({ "[", EncodedKeyOrError, "]" })
                        end

                        Output[#Output + 1] = EqualsSeperator
                    end

                    
                    if ValueIsTable then
                        local IndexPath
                        if InsertCycles and KeyIndexTypes[KeyType] and RefMaps[TablePointer] then
                            if KeyType == "string" and not LuaKeywords[Key] and string_match(Key, DirectIndexPat) then
                                IndexPath = "." .. Key
                            else
                                local EncodedKeyAsValue = TypeCases[KeyType](Key)
                                IndexPath = table_concat({ "[", EncodedKeyAsValue, "]" })
                            end
                        end

                        if not VisitedTables[Value] then
                            if IndexPath then
                                RefMaps[Value] = RefMaps[TablePointer] .. IndexPath
                            end

                            TableStack[#TableStack + 1] = { TablePointer, Key, KeyNumIndex, IsArray }

                            TablePointer = Value
                            NextKey = nil
                            KeyNumIndex = 1
                            IsArray = false 

                            IsNewTable = true
                            SkipStackPop = true

                            return false 
                        else
                            EncodedValueOrError =
                                string_format("{%s}", (OutputWarnings and "--[[LuaEncode: Duplicate reference]]") or "")

                            if IndexPath then
                                CycleMaps[IndexPath] = RefMaps[Value]
                            end
                        end
                    end

                    
                    Output[#Output + 1] = EncodedValueOrError

                    ValueWasEncoded = true
                elseif OutputWarnings then 
                    
                    
                    local ErrorMessage = string_format(
                        "LuaEncode: Failed to serialize %s of data type %s: %s",
                        (not KeyEncodedSuccess and "key") or (not ValueEncodedSuccess and "value") or "key/value",
                        ValueType,
                        (not KeyEncodedSuccess and SerializeString(EncodedKeyOrError))
                            or (not ValueEncodedSuccess and SerializeString(EncodedValueOrError))
                            or "(Failed to get error message)"
                    )

                    Output[#Output + 1] = CommentBlock(ErrorMessage)
                end

                local HasNextValue = (IsArray and Key < TablePointer["n"])
                    or (not IsArray and next(TablePointer, Key) ~= nil)
                if not HasNextValue then
                    
                    Output[#Output + 1] = NewEntryString .. EndingIndentString
                elseif ValueWasEncoded then
                    Output[#Output + 1] = ","
                end
            else
                

                
                local KeyTostring = (KeyType == "userdata" and "userdata") or tostring(Key)
                local ValueTostring = (ValueType == "userdata" and "userdata") or tostring(Value)

                Output[#Output + 1] = CommentBlock(
                    BlankSeperator
                        .. KeyType
                        .. "("
                        .. SerializeString(KeyTostring)
                        .. ")"
                        .. ":"
                        .. BlankSeperator
                        .. ValueType
                        .. "("
                        .. SerializeString(ValueTostring)
                        .. ")"
                        .. BlankSeperator
                )

                local HasNextValue = (IsArray and Key < TablePointer["n"])
                    or (not IsArray and next(TablePointer, Key) ~= nil)
                if not HasNextValue then
                    Output[#Output + 1] = NewEntryString .. EndingIndentString
                end
            end

            return true
        end

        if IsArray then
            
            local StartIndex = IsNewTable and 1 or (NextKey + 1)
            for Index = StartIndex, TablePointer["n"] do
                local Success = WalkTable(Index, rawget(TablePointer, Index))
                if not Success then
                    break
                end
            end
        else
            for Key, Value in next, TablePointer, NextKey do
                local Success = WalkTable(Key, Value)
                if not Success then
                    break
                end
            end
        end

        
        if not SkipStackPop then
            if not Prettify and IndentCount > 0 then
                Output[#Output + 1] = IndentString
            end
            Output[#Output + 1] = "}"

            if #TableStack > 0 then
                local TableUp = TableStack[#TableStack]
                TableStack[#TableStack] = nil 

                TablePointer, NextKey, KeyNumIndex, IsArray = TableUp[1], TableUp[2], TableUp[3], TableUp[4]
                IsNewTable = false
            else
                break
            end
        end
    end

    if InsertCycles then
        local CycleMapsOut = {}
        for CycleIndex, CycleMap in next, CycleMaps do
            CycleMapsOut[#CycleMapsOut + 1] = IndentString
                .. "t"
                .. CycleIndex
                .. EqualsSeperator
                .. "t"
                .. CycleMap
                .. CodegenNewline
        end

        if #CycleMapsOut > 0 then
            return table_concat({
                "(function(t)",
                NewEntryString,
                table_concat(CycleMapsOut),
                NewEntryString,
                IndentString,
                "return t",
                CodegenNewline,
                "end)(",
                table_concat(Output),
                ")",
            }),
                DidInsertNilFunction
        end
    end

    return table_concat(Output), DidInsertNilFunction
end

return LuaEncode
