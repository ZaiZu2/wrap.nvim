M = {}

local rules = require 'wrap.rules'
local temp = require 'utils' -- TODO: Temporary, delete
local tr = require 'vim.treesitter'
local utils = require 'wrap.utils'
local p = temp.pprint

local MultiFormatter = { a = 'a' }

function MultiFormatter:new(line_length, node, cur_pos, filetype)
    local row_start, col_start, _, _ = tr.get_node_range(node)
    local com_length = line_length - col_start
    local new = {
        line_length = line_length,
        com_length = com_length,
        row_start = row_start,
        col_start = col_start,
        node = node,
        cur_pos = cur_pos,
        filetype = filetype,
        symbols = utils.get_comment_symbol('multi', filetype, rules),
    }
    setmetatable(new, self)
    self.__index = self -- Provides inheritence

    return new
end

function MultiFormatter.parse(self, text)
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

function MultiFormatter:isolate_paragraph(com_lines)
    local left, right
    -- Find and isolate a paragraph
    local rel_cur_y = self.cur_pos[2] - self.row_start + 1
    left, right = utils.find_subarray(com_lines, rel_cur_y, function(str)
        return not utils.is_whitespace_only(str)
    end)
    if left == -1 then
        vim.notify 'Selected line consists only of whitespaces'
        return
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

function MultiFormatter:wrap(com_text)
    local wrapped_lines, _ = {}, nil
    local com_split_end = 1 --- @type integer|nil
    local com_split_start = 0 --- @type integer|nil

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
        if line_start + self.com_length > #com_text then
            line_end = #com_text
            is_final_substr = true
        else
            line_end = line_start + self.com_length
        end

        -- Substring a new line
        local substring = string.sub(com_text, line_start, line_end)
        if not is_final_substr then
            -- Find if the new line is not splitting a word in a middle
            -- If it does, find the closest whitespace to the left of that word
            com_split_end, _ = string.find(substring, '%s*%S*$')
            if com_split_end == nil then -- Text occupies a full line width
                com_split_end = self.com_length
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

function MultiFormatter:build_buf_lines(lines)
    -- TODO: Figure out some automatic inferrence of indentation
    -- local indent_symbol = vim.bo.expandtab and '\t' or ' '
    -- local shiftwidth = vim.fn.shiftwidth()
    -- local indents_no = math.floor(self.col_start / vim.fn.shiftwidth()) + 1
    -- local indent = indent_symbol:rep(shiftwidth * indents_no)

    local buffer_lines = {}
    local indent = string.rep(' ', self.col_start)
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

function SingleFormatter:new()
    local new = {}
    setmetatable(new, { __index = self })
    self.__index = self
    return new
end

function SingleFormatter:parse(text) end

function SingleFormatter:find_adjacent_nodes(node, bufnr) end

function SingleFormatter:wrap(com_text, length) end

function SingleFormatter:build_buffer_lines(lines) end

return {
    MultiFormatter = MultiFormatter,
    SingleFormatter = SingleFormatter,
}
