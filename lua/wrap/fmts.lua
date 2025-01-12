local tr = require 'vim.treesitter'
local utils = require 'wrap.utils'

---@class Formatter
---@field tokens table
---@field matched_token [string, string?]|nil
---@field filetype string
---@field bufnr number
---@field init_node TSNode
---@field init_node_range [number, number, number, number]
---@field rel_cur_y number|nil

---@class FormatterOpts
---@field tokens table
---@field filetype string
---@field bufnr number
---@field init_node TSNode
---@field cur_y number

---@class Formatter
local Formatter = {}
---@return Formatter
function Formatter:new()
    self.__index = self -- Provides inheritence
    local obj = {}
    setmetatable(obj, self)
    return obj
end

function Formatter:wrap(com_text, com_length)
    local wrapped_lines, _ = {}, nil
    local com_split_end = 1 --- @type integer?
    local com_split_start = 0 --- @type integer?

    local is_final_substr = false
    -- Iterate over `comment`, cutting chunks out of it and building lines out of it
    while not is_final_substr do
        com_text = string.sub(com_text, com_split_start + com_split_end, -1)
        -- Skip over leading whitspaces first
        _, com_split_start = string.find(com_text, '^%s*')
        if com_split_start == nil then
            com_split_start = 1
        else
            com_split_start = com_split_start + 1
        end

        -- Find limits of a new line, accounting for comment length available left
        local line_start = com_split_start
        local line_end
        if line_start + com_length > #com_text then
            line_end = #com_text
            is_final_substr = true
        else
            line_end = line_start + com_length
        end

        -- Substring a new line
        local substring = string.sub(com_text, line_start, line_end)
        if not is_final_substr then
            -- Find if the new line is not splitting a word in a middle
            -- If it does, find the closest whitespace to the left of that word
            com_split_end, _ = string.find(substring, '%s*%S*$')
            if com_split_end == nil then -- Text occupies a full line width
                com_split_end = com_length
            -- TODO: Line might consist of only whitespaces (?), this is not handled here
            else
                com_split_end = com_split_end - 1
            end
            substring = string.sub(substring, 1, com_split_end)
        end

        table.insert(wrapped_lines, substring)
    end
    return wrapped_lines
end

function Formatter:isolate_paragraph(com_lines, index)
    local left, right
    -- Find and isolate a paragraph
    left, right = utils.find_subarray(com_lines, index, function(str)
        return not utils.is_whitespace_only(str)
    end)
    if left == -1 then
        return nil
    end
    return table.move(com_lines, left, right, 1, {}), left, right
end

function Formatter:merge_paragraph(com_lines, lead_wtspcs, paragraph_lines, left, right)
    local merged_lines = vim.list_slice(com_lines, 1, left - 1)
    local end_slice = vim.list_slice(com_lines, right + 1, #com_lines)
    vim.list_extend(merged_lines, paragraph_lines)
    vim.list_extend(merged_lines, end_slice)

    -- Extend whitespace list to retain correct line to whitespace association
    local paragraph_wtspcs = {}
    for _ = 1, #paragraph_lines do
        table.insert(paragraph_wtspcs, lead_wtspcs[self.rel_cur_y])
    end
    local merged_wtspcs = vim.list_slice(lead_wtspcs, 1, left - 1)
    local end_wtsp_slice = vim.list_slice(lead_wtspcs, right + 1, #lead_wtspcs)
    vim.list_extend(merged_wtspcs, paragraph_wtspcs)
    vim.list_extend(merged_wtspcs, end_wtsp_slice)

    return merged_lines, merged_wtspcs
end

-----------------------------------------------------------------------------------------

---@class MultiFormatter:Formatter
local MultiFormatter = {}

---@param opts FormatterOpts
---@return MultiFormatter
function MultiFormatter:new(opts)
    self.__index = self
    setmetatable(self, { __index = Formatter })

    local obj = Formatter:new()
    obj.tokens = opts.tokens
    obj.matched_token = nil
    obj.filetype = opts.filetype
    obj.bufnr = opts.bufnr
    obj.init_node = opts.init_node
    obj.init_node_range = { tr.get_node_range(obj.init_node) }
    obj.rel_cur_y = opts.cur_y - obj.init_node_range[1] + 1
    setmetatable(obj, self)
    return obj ---@type MultiFormatter
end

function MultiFormatter:parse(text)
    local com_text
    for _, token in ipairs(self.tokens) do
        -- Parse comment content out of a raw string
        local prefix_rgx = '^%s*' .. utils.escape(token[1]) -- Match opening token
        local body_rgx = '(.*)' -- Match comment content with all whitespaces and newline chars
        local suffix_rgx = utils.escape(token[2]) .. '%s*$' -- Match closing token
        com_text = string.match(text, prefix_rgx .. body_rgx .. suffix_rgx)
        if com_text ~= nil then
            self.matched_token = token
            break
        end
    end
    -- TODO: Implement inferred parsing

    if com_text == nil then
        error(('Failed to match multiline %s comment - `%s`'):format(self.filetype, text))
    end

    -- Split comment content into lines
    com_text = com_text .. '\n' -- Needed for capturing last line
    local com_lines = {}
    local lead_wtspcs = {}
    for line in com_text:gmatch '(.-)\n' do -- Match groups separated by \n (split string)
        local lead_wtspc, trimmed_line = string.match(line, '^(%s*)(.-)%s*$')
        table.insert(com_lines, trimmed_line)
        table.insert(lead_wtspcs, lead_wtspc or '')
    end
    return com_lines, lead_wtspcs
end

function MultiFormatter:build_buf_whole(lines)
    local indent_char, indent_lvl = utils.calculate_indent(self.init_node_range[2])
    local indent = string.rep(indent_char, indent_lvl)

    local buffer_lines = {}
    for i, line in ipairs(lines) do
        local buffer_line
        if #lines == 1 then -- If comment spans only 1 line
            buffer_line = self.matched_token[1] .. line .. self.matched_token[2]
        elseif i == 1 then -- If first line
            buffer_line = self.matched_token[1] .. line
        elseif i == #lines then -- If last line
            buffer_line = indent .. line .. self.matched_token[2]
        else -- If a generic line
            buffer_line = utils.is_whitespace_only(line) and '' or indent .. line
        end
        table.insert(buffer_lines, buffer_line)
    end
    return buffer_lines
end

function MultiFormatter:build_buf_paragraph(lines, lead_wtspcs)
    local buffer_lines = {}
    for i, line in ipairs(lines) do
        local buffer_line
        if #lines == 1 then -- If comment spans only 1 line
            buffer_line = self.matched_token[1] .. line .. self.matched_token[2]
        elseif i == 1 then -- If first line
            buffer_line = self.matched_token[1] .. line
        elseif i == #lines then -- If last line
            buffer_line = lead_wtspcs[i] .. line .. self.matched_token[2]
        else -- If a generic line
            buffer_line = utils.is_whitespace_only(line) and '' or lead_wtspcs[i] .. line
        end
        table.insert(buffer_lines, buffer_line)
    end
    return buffer_lines
end

-----------------------------------------------------------------------------------------

---@class SingleFormatter:Formatter
---@field cur_y number
local SingleFormatter = {}

--- @param opts FormatterOpts
--- @return SingleFormatter
function SingleFormatter:new(opts)
    self.__index = self
    setmetatable(self, { __index = Formatter })

    local obj = Formatter:new()
    obj.tokens = opts.tokens
    obj.matched_token = nil
    obj.filetype = opts.filetype
    obj.bufnr = opts.bufnr
    obj.init_node = opts.init_node
    obj.init_node_range = { tr.get_node_range(obj.init_node) }
    obj.cur_y = opts.cur_y
    setmetatable(obj, self)
    return obj ---@type SingleFormatter
end

function SingleFormatter:parse(com_text)
    local com_body
    for _, token in ipairs(self.tokens) do
        local prefix_rgx = '^%s*' .. utils.escape(token[1]) -- Match opening token
        local body_rgx = '%s*(.-)%s*$' -- Match comment content, but strip all outer whitespaces
        com_body = string.match(com_text, prefix_rgx .. body_rgx)

        if com_body ~= nil then
            self.matched_token = token
            return com_body
        end
    end
    -- TODO: Implement inferred parsing
    -- infer_singleline()

    if com_body == nil then
        vim.notify(
            ('Failed to parse one of the single-line %s comments - `%s`'):format(
                self.filetype,
                com_text
            )
        )
        error(
            ('Failed to parse one of the single-line %s comments - `%s`'):format(
                self.filetype,
                com_text
            )
        )
    end
end

function SingleFormatter:parse_block(com_nodes)
    local com_lines = {}
    for _, node in ipairs(com_nodes) do
        local com_text = tr.get_node_text(node, self.bufnr)
        local com_line = self:parse(com_text)
        -- TODO: Add error handling to `parse`
        table.insert(com_lines, com_line)
    end
    return com_lines
end

function SingleFormatter:find_adjacent_nodes(node)
    local initial_type = node:type()
    local cur_start, _, cur_end, _ = tr.get_node_range(node)
    local found_nodes = { node }

    -- Find upward row-adjacent comments
    local prev_node = node ---@type TSNode?
    while prev_node ~= nil do -- Acts as a type guard so LSP does not complain
        prev_node = prev_node:prev_named_sibling()
        if prev_node == nil then
            break
        end

        local prev_start, _, prev_end, _ = tr.get_node_range(prev_node)
        if prev_node:type() ~= initial_type or cur_start - prev_end > 1 then
            break
        end
        cur_start = prev_start
        table.insert(found_nodes, 1, prev_node) -- Prepend to table
    end

    -- Find downward row-adjacent comments
    local next_node = node ---@type TSNode?
    while next_node ~= nil do -- Acts as a type guard so LSP does not complain
        next_node = next_node:next_named_sibling()
        if next_node == nil then
            break
        end

        local next_start, _, next_end, _ = tr.get_node_range(next_node)
        if next_node:type() ~= initial_type or next_start - cur_end > 1 then
            break
        end
        cur_end = next_end
        table.insert(found_nodes, next_node)
    end

    return found_nodes
end

function SingleFormatter:build_buf_lines(lines, start_node)
    -- First line must be merged from the existing one in case of an inline comment.
    -- Final comment indentation depends on the selected line, hence newly
    -- wrapped lines might overwrite the commented code.
    local first_row_start, first_col_start, _, _ = tr.get_node_range(start_node)
    local new_col_start = self.init_node_range[2]

    local indent_char, indent_lvl = utils.calculate_indent(new_col_start)
    local indent = string.rep(indent_char, indent_lvl)

    local start_line = vim.api.nvim_buf_get_text(self.bufnr, first_row_start, 0, first_row_start, first_col_start, {})[1]
    -- Calculate the final offset of the first comment line in reference to potential code
    local col_start_diff = new_col_start - first_col_start
    local inline_code
    if col_start_diff > 0 then
        inline_code = start_line .. string.rep(' ', col_start_diff)
    else
        inline_code = start_line:sub(1, new_col_start - 1)
        inline_code = inline_code .. (inline_code ~= '' and ' ' or '')
    end

    local buffer_lines = {}
    buffer_lines[1] = inline_code .. self.matched_token[1] .. ' ' .. lines[1] -- First line is already appended on `nvim_buf_set_text`
    for i = 2, #lines do
        buffer_lines[i] = indent .. self.matched_token[1] .. ' ' .. lines[i]
    end
    return buffer_lines
end

-----------------------------------------------------------------------------------------

return {
    MultiFormatter = MultiFormatter,
    SingleFormatter = SingleFormatter,
}
