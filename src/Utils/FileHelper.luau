local FileHelper = {}
FileHelper.__index = FileHelper

local function IsFilesystemAvailable(): boolean
    local ExecutorSupport = wax.shared.ExecutorSupport
    return ExecutorSupport ~= nil
        and ExecutorSupport.FileSystem ~= nil
        and ExecutorSupport.FileSystem.IsWorking
end


function FileHelper.new(basePath: string)
    local self = setmetatable({
        BasePath = FileHelper.NormalizePath(basePath),
    }, FileHelper)

    self:EnsureDirectory()
    return self
end


function FileHelper:EnsureDirectory()
    if not IsFilesystemAvailable() then return end

    local paths = {}
    local parts = self.BasePath:split("/")

    for idx = 1, #parts do
        if parts[idx] == "" then continue end
        paths[#paths + 1] = table.concat(parts, "/", 1, idx)
    end

    for i = 1, #paths do
        local str = paths[i]
        if isfolder(str) then continue end
        makefolder(str)
    end
end


function FileHelper:GetPath(relativePath: string)
    local normalizedPath = self.NormalizePath(relativePath or "")
    
    if self.BasePath == "" then
        return normalizedPath
    end
    
    if self.BasePath:sub(-1) == "/" then
        return self.BasePath .. normalizedPath
    end
    
    if normalizedPath == "" then
        return self.BasePath
    end
    
    return self.BasePath .. "/" .. normalizedPath
end


function FileHelper.NormalizePath(path: string)
    if type(path) ~= "string" then return "" end
    return path:gsub("\\", "/")
end


function FileHelper:GetRelativePath(path: string)
    path = self.NormalizePath(path)
    local basePath = self.NormalizePath(self.BasePath)
    if basePath:sub(-1) ~= "/" then
        basePath = basePath .. "/"
    end
    
    local Start, End = string.find(path, basePath, 1, true)
    if Start then
        return string.sub(path, End + 1)
    end
    
    return path
end


function FileHelper:EnsureFile(relativePath: string, default: string)
    if not IsFilesystemAvailable() then return end

    relativePath = self.NormalizePath(relativePath or "")
    
    if not isfile(self:GetPath(relativePath)) then
        writefile(self:GetPath(relativePath), default)
    end
end


function FileHelper:DoesExist(relativePath: string)
    if not IsFilesystemAvailable() then return false end

    relativePath = self.NormalizePath(relativePath or "")
    local path = self:GetPath(relativePath)

    local fileSuccess = pcall(assert, isfile(path), "File does not exist.")
    local folderSuccess = pcall(assert, isfolder(path), "Directory does not exist.")

    return fileSuccess or folderSuccess
end


function FileHelper:ReadFile(relativePath: string)
    if not IsFilesystemAvailable() then return nil end

    relativePath = self.NormalizePath(relativePath or "")
    return readfile(self:GetPath(relativePath))
end


function FileHelper:ReadRawFile(path: string)
    if not IsFilesystemAvailable() then return nil end

    return readfile(path)
end


function FileHelper:WriteFile(relativePath: string, data: string)
    if not IsFilesystemAvailable() then return end

    relativePath = self.NormalizePath(relativePath or "")
    
    writefile(self:GetPath(relativePath), data)
end


function FileHelper:AppendFile(relativePath: string, data: string)
    if not IsFilesystemAvailable() then return end

    relativePath = self.NormalizePath(relativePath or "")
    
    appendfile(self:GetPath(relativePath), data)
end


function FileHelper:DeleteFile(relativePath: string)
    if not IsFilesystemAvailable() then return end

    relativePath = self.NormalizePath(relativePath or "")
    
    if isfile(self:GetPath(relativePath)) then
        delfile(self:GetPath(relativePath))
    end
end


function FileHelper:DeleteDirectory(relativePath: string)
    if not IsFilesystemAvailable() then return end

    relativePath = self.NormalizePath(relativePath or "")
    
    if isfolder(self:GetPath(relativePath)) then
        delfolder(self:GetPath(relativePath))
    end
end


function FileHelper:ListFiles(relativePath: string?)
    if not IsFilesystemAvailable() then return {} end

    relativePath = self.NormalizePath(relativePath or "")
    
    local files = {}
    for _, file in listfiles(self:GetPath(relativePath)) do
        table.insert(files, self:GetRelativePath(file))
    end

    return files
end


function FileHelper:GetFileName(relativePath: string)
    relativePath = self.NormalizePath(relativePath or "")
    
    return relativePath:match("[^/]+$")
end


function FileHelper:ListFileNames(relativePath: string?)
    relativePath = self.NormalizePath(relativePath or "")
    
    local names = {}
    for _, file in self:ListFiles(relativePath) do
        table.insert(names, self:GetFileName(file))
    end

    return names
end

return FileHelper
