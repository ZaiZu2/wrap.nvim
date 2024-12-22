M = {}

local rules = require 'wrap.rules'
local temp = require 'utils' -- TODO: Temporary, delete
local tr = require 'vim.treesitter'
local utils = require 'wrap.utils'
local p = temp.pprint

local MultiFormatter = { a = 'a' }

function MultiFormatter:new(filetype)
    local new = {
        filetype = filetype,
        symbols = utils.get_comment_symbol('multi', filetype, rules),
    }
    setmetatable(new, self)
    self.__index = self -- Provides inheritence

    return new
end

function MultiFormatter:parse(text)
    local com_text
    -- Parse comment content out of a raw string
    if self.symbols ~= nil then
        local prefix_rgx = '^%s*' .. utils.escape(self.symbols[1]) -- Match opening symbol
        local body_rgx = '(.*)' -- Match comment content with all whitespaces and newline chars
        local suffix_rgx = utils.escape(self.symbols[2]) .. '%s*$' -- Match closing symbol
        com_text = string.match(text, prefix_rgx .. body_rgx .. suffix_rgx)
    else
        -- TODO: Implement inferred parsing
    end

    if com_text == nil then
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

function MultiFormatter:isolate_paragraph(com_lines, index)
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

function MultiFormatter:merge_paragraph(com_lines, paragraph_lines, left, right)
    local merged_lines = vim.list_slice(com_lines, 1, left - 1)
    local end_slice = vim.list_slice(com_lines, right + 1, #com_lines)
    vim.list_extend(merged_lines, paragraph_lines)
    vim.list_extend(merged_lines, end_slice)
    return merged_lines
end

function MultiFormatter:build_buf_lines(lines, col_start)
    local indent_char, indent_lvl = utils.calculate_indent(col_start)
    local indent = string.rep(indent_char, indent_lvl)

    local buffer_lines = {}
    for i, line in ipairs(lines) do
        local buffer_line, space
        space = utils.is_whitespace_only(line) and '' or ' ' -- Ternary expr alternative
        if #lines == 1 then -- If comment spans only 1 line
            buffer_line = indent .. self.symbols[1] .. space .. line .. space .. self.symbols[2]
        elseif i == 1 then -- If first line
            buffer_line = indent .. self.symbols[1] .. space .. line
        elseif i == #lines then -- If last line
            buffer_line = indent .. line .. space .. self.symbols[2]
        else -- If a generic line
            buffer_line = indent .. line
        end
        table.insert(buffer_lines, buffer_line)
    end
    return buffer_lines
end

-----------------------------------------------------------------------------------------

local SingleFormatter = {}

function SingleFormatter:new(filetype)
    local new = {
        filetype = filetype,
        symbols = utils.get_comment_symbol('single', filetype, rules),
    }
    setmetatable(new, { __index = self })
    self.__index = self
    return new
end

function SingleFormatter:parse(com_text)
    local com_body
    if self.symbols ~= nil then
        -- Some languages have multiple symbols denoting a single-line comment
        for _, symbol in ipairs(self.symbols) do
            local prefix_rgx = '^%s*' .. utils.escape(symbol) -- Match opening symbol
            local body_rgx = '%s*(.-)%s*$' -- Match comment content, but strip all outer whitespaces
            com_body = string.match(com_text, prefix_rgx .. body_rgx)
        end
    else
        -- TODO: Implement inferred parsing
        -- infer_singleline()
    end

    if com_body == nil then
        vim.notify(('Failed to parse one of the single-line %s comments - `%s`'):format(self.filetype, com_text))
        error(('Failed to parse one of the single-line %s comments - `%s`'):format(self.filetype, com_text))
    end
    return com_body
end

function SingleFormatter:parse_block(com_nodes, bufnr)
    local com_lines = {}
    for _, node in ipairs(com_nodes) do
        local com_text = tr.get_node_text(node, bufnr)
        local com_line = self:parse(com_text)
        table.insert(com_lines, com_line)
    end
    return com_lines
end

function SingleFormatter:find_adjacent_nodes(node, bufnr)
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
        local prev_text = tr.get_node_text(prev_node, bufnr)
        if prev_node:type() ~= initial_type or cur_start - prev_end > 1 or utils.is_whitespace_only(prev_text) then
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
        local next_text = tr.get_node_text(next_node, bufnr)
        if next_node:type() ~= initial_type or next_start - cur_end > 1 or utils.is_whitespace_only(next_text) then
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
        buffer_lines[i] = indent .. self.symbols[1] .. ' ' .. line
    end
    return buffer_lines
end

return {
    MultiFormatter = MultiFormatter,
    SingleFormatter = SingleFormatter,
}
