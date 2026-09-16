local Codec = require(script.Parent.Codec)

local LookupModule = {
	Instance = {
		Lookup = {},
	},
}

local GetInstanceIdBrokenExecutors = {
    ["Synapse Z"] = true,
}

local GetInstanceByID = (
	not GetInstanceIdBrokenExecutors[wax.shared.ExecutorName] and
	(raknet and raknet.get_instance_by_id)
)

local function IndexInstance(instance: Instance)
	local Success, DebugId = pcall(instance.GetDebugId, instance)
	if not Success then
		return
	end

	LookupModule.Instance.Lookup[DebugId] = cloneref(instance)
end

local function UnindexInstance(instance: Instance)
	local Success, DebugId = pcall(instance.GetDebugId, instance)
	if not Success then
		return
	end

	LookupModule.Instance.Lookup[DebugId] = nil
end

function LookupModule.Instance.ByRef(ref: Codec.InstanceRef): Instance?
	if ref.is_null then
		return nil
	end

	if GetInstanceByID then
		return GetInstanceByID(ref.peer_id, ref.instance_id)
	end

	local DebugIdKey = string.format("%d_%d", ref.peer_id, ref.instance_id)
	return LookupModule.Instance.Lookup[DebugIdKey]
end

function LookupModule.Instance.Build()
	if GetInstanceByID then
		return
	end

	LookupModule.DescendantAdded = wax.shared.Connect(game.DescendantAdded:Connect(IndexInstance))
	LookupModule.DescendantRemoving = wax.shared.Connect(game.DescendantRemoving:Connect(UnindexInstance))

	for _, category in { game:GetDescendants(), getnilinstances and getnilinstances() } do
		for _, instance in category do
			IndexInstance(instance)
		end
	end
end

function LookupModule.Instance.Destroy()
	if GetInstanceByID then
		return
	end

	
	if LookupModule.DescendantAdded then
		wax.shared.Disconnect(LookupModule.DescendantAdded)
		LookupModule.DescendantAdded = nil
	end

	if LookupModule.DescendantRemoving then
		wax.shared.Disconnect(LookupModule.DescendantRemoving)
		LookupModule.DescendantRemoving = nil
	end

	
	table.clear(LookupModule.Instance.Lookup)
end

return LookupModule
