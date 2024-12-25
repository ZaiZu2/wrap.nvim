M = {}

local rules = require 'wrap.rules'
local temp = require 'utils' -- TODO: Temporary, delete
local tr = require 'vim.treesitter'
local utils = require 'wrap.utils'
local p = temp.pprint

local Formatter = {} -- Inherit from Formatter
function Formatter:new(symbols, filetype)
    self.__index = self -- Provides inheritence
    local new = { symbols = symbols, matched_symbol = nil, filetype = filetype }
    setmetatable(new, self)
    return new
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

function Formatter:merge_paragraph(com_lines, paragraph_lines, left, right)
    local merged_lines = vim.list_slice(com_lines, 1, left - 1)
    local end_slice = vim.list_slice(com_lines, right + 1, #com_lines)
    vim.list_extend(merged_lines, paragraph_lines)
    vim.list_extend(merged_lines, end_slice)
    return merged_lines
end

-----------------------------------------------------------------------------------------

local CustomFormatter = {}
function CustomFormatter:new(symbols, filetype)
    self.__index = self
    setmetatable(self, { __index = Formatter })

    local new = Formatter:new(symbols, filetype)
    setmetatable(new, self)
    return new
end

function CustomFormatter:parse(text)
    text = text .. '\n' -- Needed for capturing last line
    p { text = text }
    local com_lines = {}
    for line in text:gmatch '(.-)\n' do -- Match groups separated by \n (split string)
        local trimmed_line = string.match(line, '^%s*(.-)%s*$')
        table.insert(com_lines, trimmed_line)
    end
    return com_lines
end

function CustomFormatter:build_buf_lines(lines, col_start)
    local indent_char, indent_lvl = utils.calculate_indent(col_start)
    local indent = string.rep(indent_char, indent_lvl)

    local buffer_lines = {}
    for i, line in ipairs(lines) do
        local buffer_line, space
        space = utils.is_whitespace_only(line) and '' or ' ' -- Ternary expr alternative
        if #lines == 1 then -- If comment spans only 1 line
            buffer_line = line
        elseif i == 1 then -- If first line
            buffer_line = line
        elseif i == #lines then -- If last line
            buffer_line = line
        else -- If a generic line
            buffer_line = indent .. line
        end
        table.insert(buffer_lines, buffer_line)
    end
    return buffer_lines
end

-----------------------------------------------------------------------------------------

local MultiFormatter = {}
function MultiFormatter:new(symbols, filetype)
    self.__index = self
    setmetatable(self, { __index = Formatter })

    local new = Formatter:new(symbols, filetype)
    setmetatable(new, self)
    return new
end

function MultiFormatter:parse(text)
    local com_text
    for _, symbol in ipairs(self.symbols) do
        -- Parse comment content out of a raw string
        local prefix_rgx = '^%s*' .. utils.escape(symbol[1]) -- Match opening symbol
        local body_rgx = '(.*)' -- Match comment content with all whitespaces and newline chars
        local suffix_rgx = utils.escape(symbol[2]) .. '%s*$' -- Match closing symbol
        com_text = string.match(text, prefix_rgx .. body_rgx .. suffix_rgx)
        if com_text ~= nil then
            self.matched_symbol = symbol
            break
        end
    end
    -- TODO: Implement inferred parsing

    if com_text == nil then
        vim.notify(('Failed to match multiline %s comment - `%s`'):format(self.filetype, text))
        error(('Failed to match multiline %s comment - `%s`'):format(self.filetype, text))
    end

    -- Split comment content into lines
    com_text = com_text .. '\n' -- Needed for capturing last line
    local com_lines = {}
    for line in com_text:gmatch '(.-)\n' do -- Match groups separated by \n (split string)
        local trimmed_line = string.match(line, '^%s*(.-)%s*$')
        table.insert(com_lines, trimmed_line)
    end
    return com_lines
end

function MultiFormatter:build_buf_lines(lines, col_start)
    local indent_char, indent_lvl = utils.calculate_indent(col_start)
    local indent = string.rep(indent_char, indent_lvl)

    local buffer_lines = {}
    for i, line in ipairs(lines) do
        local buffer_line, space
        p { matched_symbol = self.matched_symbol }
        space = utils.is_whitespace_only(line) and '' or ' ' -- Ternary expr alternative
        if #lines == 1 then -- If comment spans only 1 line
            buffer_line = indent
                .. self.matched_symbol[1]
                .. space
                .. line
                .. space
                .. self.matched_symbol[2]
        elseif i == 1 then -- If first line
            buffer_line = indent .. self.matched_symbol[1] .. space .. line
        elseif i == #lines then -- If last line
            buffer_line = indent .. line .. space .. self.matched_symbol[2]
        else -- If a generic line
            buffer_line = indent .. line
        end
        table.insert(buffer_lines, buffer_line)
    end
    return buffer_lines
end

-----------------------------------------------------------------------------------------

local SingleFormatter = {}
function SingleFormatter:new(symbols, filetype)
    self.__index = self
    setmetatable(self, { __index = Formatter })

    local new = Formatter:new(symbols, filetype)
    setmetatable(new, self)
    return new
end

function SingleFormatter:parse(com_text)
    local com_body
    p {single_symbols = self.symbols}
    for _, symbol in ipairs(self.symbols) do
        local prefix_rgx = '^%s*' .. utils.escape(symbol[1]) -- Match opening symbol
        local body_rgx = '%s*(.-)%s*$' -- Match comment content, but strip all outer whitespaces
        com_body = string.match(com_text, prefix_rgx .. body_rgx)

        if com_body ~= nil then
            self.matched_symbol = symbol
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

function SingleFormatter:parse_block(com_nodes, bufnr)
    local com_lines = {}
    for _, node in ipairs(com_nodes) do
        local com_text = tr.get_node_text(node, bufnr)
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

function SingleFormatter:build_buf_lines(lines, col_start)
    local indent_char, indent_lvl = utils.calculate_indent(col_start)
    local indent = string.rep(indent_char, indent_lvl)

    local buffer_lines = {}
    for i, line in ipairs(lines) do
        buffer_lines[i] = indent .. self.matched_symbol[1] .. ' ' .. line
    end
    return buffer_lines
end

-----------------------------------------------------------------------------------------

return {
    CustomFormatter = CustomFormatter,
    MultiFormatter = MultiFormatter,
    SingleFormatter = SingleFormatter,
}
