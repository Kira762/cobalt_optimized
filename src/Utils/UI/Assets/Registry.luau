-- Local asset manifest.
--
-- Cobalt used to fetch these files from several third-party hosts during boot.
-- The manifest now points only at files shipped with this repository.  When a
-- local file is unavailable, the Roblox asset id is used as a compatibility
-- fallback; no HTTP request is made by the asset system.

export type FontAsset = {
	Type: "Font",
	FileName: string,
	FamilyName: string,
	FallbackId: number,
	LocalPath: string?,
}

export type ImageAsset = {
	Type: "Image",
	FileName: string,
	LocalPath: string?,
	FallbackId: string,
	Group: string?,
}

export type Asset = FontAsset | ImageAsset

local Registry: { [string]: Asset } = {
	Inter = {
		Type = "Font",
		FileName = "Inter.ttf",
		FamilyName = "Inter",
		FallbackId = 12187365364,
		-- The UI uses the Roblox fallback for fonts.  Keeping the font out of the
		-- runtime download path makes a one-file copy work on every executor.
		LocalPath = nil,
	},
	IBMPlexMono = {
		Type = "Font",
		FileName = "IBMPlexMono.ttf",
		FamilyName = "IBM Plex Mono",
		FallbackId = 16658246179,
		LocalPath = nil,
	},
	Logo = {
		Type = "Image",
		FileName = "cobalt-logo.png",
		LocalPath = "assets/cobalt-logo.png",
		FallbackId = "rbxassetid://91685317120520",
	},
	RemoteEvent = {
		Group = "InstanceClass",
		Type = "Image",
		FileName = "RemoteEvent.png",
		LocalPath = "assets/remote-event.png",
		FallbackId = "rbxassetid://110803789420086",
	},
	UnreliableRemoteEvent = {
		Group = "InstanceClass",
		Type = "Image",
		FileName = "UnreliableRemoteEvent.png",
		LocalPath = "assets/unreliable-remote-event.png",
		FallbackId = "rbxassetid://126244162339059",
	},
	RemoteFunction = {
		Group = "InstanceClass",
		Type = "Image",
		FileName = "RemoteFunction.png",
		LocalPath = "assets/remote-function.png",
		FallbackId = "rbxassetid://108537517159060",
	},
	BindableEvent = {
		Group = "InstanceClass",
		Type = "Image",
		FileName = "BindableEvent.png",
		LocalPath = "assets/bindable-event.png",
		FallbackId = "rbxassetid://116839398727495",
	},
	BindableFunction = {
		Group = "InstanceClass",
		Type = "Image",
		FileName = "BindableFunction.png",
		LocalPath = "assets/bindable-function.png",
		FallbackId = "rbxassetid://112264959079193",
	},
}

return Registry
