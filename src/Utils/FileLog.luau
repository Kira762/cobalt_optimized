





local Logger = {}
Logger.__index = Logger

local FileHelper = require(script.Parent.FileHelper)

Logger.LOG_LEVELS = {
	ERROR = 1,
	WARNING = 2,
	INFO = 3,
	DEBUG = 4,
}

local LOG_LEVEL_STRINGS = {
	[Logger.LOG_LEVELS.ERROR] = "ERROR",
	[Logger.LOG_LEVELS.WARNING] = "WARNING",
	[Logger.LOG_LEVELS.INFO] = "INFO",
	[Logger.LOG_LEVELS.DEBUG] = "DEBUG",
}

local startTime = tick()

local function SplitFilePath(path: string): (string, string)
	local normalizedPath = FileHelper.NormalizePath(path)
	local directory, fileName = normalizedPath:match("^(.*)/([^/]*)$")

	return directory or "", fileName or normalizedPath
end


function Logger:GenerateFileName()
	local JobIdNumber = game.JobId:gsub("%D", "")
	local timestamp = os.date("!%Y%m%d%H%M%S")
	local fileName = `{JobIdNumber * 1.7 // 1.8}_{timestamp}.log`

	if self.logFileDirectory == "" then
		return fileName
	end

	return `{self.logFileDirectory}/{fileName}`
end


function Logger.new(logFilePath: string, logLevel: number?, overwrite: boolean?)
	local self = setmetatable({}, Logger)
	local logFileDirectory, logFileName = SplitFilePath(logFilePath)

	self.fileHelper = FileHelper.new(logFileDirectory)
	self.logFileName = logFileName
	self.logFileDirectory = logFileDirectory
	self.logFilePath = self.fileHelper:GetPath(logFileName)
	self.logLevel = logLevel or Logger.LOG_LEVELS.INFO
	self.overwrite = overwrite or false

	local success, err = pcall(function()
		if self.overwrite then
			self.fileHelper:WriteFile(self.logFileName, "")
		else
			self.fileHelper:EnsureFile(self.logFileName, "")
		end
	end)
	if not success then
		warn(debug.traceback(`Failed to initialize log file: {self.logFilePath} - {err}`, 2))
	end

	self:Info("Logger", "Logger initialized")

	return self
end


function Logger:Log(level: number, threadId: string, message: string)
	if level <= self.logLevel then
		local levelStr = LOG_LEVEL_STRINGS[level]

		local timestamp = `{os.date("!%Y-%m-%dT%H:%M:%S")}{("%.3f"):format(tick() % 1)}Z`
		local elapsedTime = ("%.6f"):format(tick() - startTime)

		local logMessage = `{timestamp},{elapsedTime},{threadId},{levelStr} {message}\n`

		local success, err = pcall(self.fileHelper.AppendFile, self.fileHelper, self.logFileName, logMessage)
		if not success then
			warn(debug.traceback(`Failed to write to log file: {self.logFilePath} - {err}`, 2))
		end
	end
end


function Logger:Debug(threadId: string, message: string)
	self:Log(Logger.LOG_LEVELS.DEBUG, threadId, message)
end


function Logger:Info(threadId: string, message: string)
	self:Log(Logger.LOG_LEVELS.INFO, threadId, message)
end


function Logger:Warning(threadId: string, message: string)
	self:Log(Logger.LOG_LEVELS.WARNING, threadId, message)
end


function Logger:Error(threadId: string, message: string)
	self:Log(Logger.LOG_LEVELS.ERROR, threadId, message)
end

return Logger
