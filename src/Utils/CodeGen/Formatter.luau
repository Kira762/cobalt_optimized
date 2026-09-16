local Formatter = {}



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



function Formatter.FormatLuaArray(Values: { any }): string
	local Serialized = {}
	for _, Value in Values do
		local Literal = Formatter.FormatLuaLiteral(Value)
		if not Literal then
			return "{}"
		end

		table.insert(Serialized, Literal)
	end

	return "{ " .. table.concat(Serialized, ", ") .. " }"
end


function Formatter.IndentCode(Code: string, IndentLevel: number)
	local Indent = IndentTemplate:rep(IndentLevel)
	local IndentedCode = Code:gsub("\n", "\n" .. Indent)
	return Indent .. IndentedCode
end


function Formatter.CreateArgsString(SerializedArgs: string, Args: { [number]: any, n: number }, Prefix: string?)
	if Args.n == 0 then
		return ""
	end

	
	if string.sub(SerializedArgs, 1, 9) == "(function" then
		return `{Prefix == nil and "" or Prefix}table.unpack({SerializedArgs}, 1, {Args.n})`
	end

	
	return `{Prefix == nil and "" or Prefix}{string.sub(SerializedArgs, 2, #SerializedArgs - 1)}`
end

return Formatter
