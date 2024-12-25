---@alias CustomNode table<string,string[]>

---@class (exact) LanguageRules
---@field single string[]?
---@field multi string[]?
---@field custom table<string,CustomNode>

---@alias Rules table<string, LanguageRules>
