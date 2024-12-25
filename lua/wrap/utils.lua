M = {}
local temp = require 'utils' -- TODO: Temporary, delete
local p = temp.pprint

---Escape regex magic characters
---@param str string
---@return string str Escaped string
function M.escape(str)
    local escaped, _ = string.gsub(str, '[.*+?^$()[%%-]', '%%%0')
    return escaped
end

--- Get the indentation character and level based on the given indent length.
---@param indent_length number: Length of the indentation.
---@return string, number: Character used for indentation and the indentation level.
function M.calculate_indent(indent_length)
    local indent_lvl, indent_char
    local shiftwidth = vim.bo.shiftwidth
    if vim.bo.expandtab then
        indent_lvl = indent_length / shiftwidth
        indent_char = (' '):rep(shiftwidth)
    else
        indent_lvl = indent_length / vim.bo.tabstop
        indent_char = '\t'
    end
    indent_lvl = math.floor(indent_lvl)
    return indent_char, indent_lvl
end

---Check if the string consist of whitespaces only
---@param str string
---@return boolean
function M.is_whitespace_only(str)
    return not not string.match(str, '^%s*$')
end

---Traverse TS tree inwards first and then outwards in search of a closest node of a provided type
---@param start_node TSNode
---@param types string[] Array of TSNode types to search for
---@param inwards_only boolean? Traverse into children only
---@return TSNode|nil, string|nil
function M.find_node(start_node, types, inwards_only)
    inwards_only = inwards_only or false

    for _, type_ in ipairs(types) do
        -- -- TODO: Is inwards recursion needed?
        -- -- Search inward first
        -- local node = start_node ---@type TSNode?
        -- while node ~= nil do
        --     p { looped_in = node:type() }
        --     if node:type() == type_ then
        --         return node, type_
        --     end
        --     node = node:named_child(1)
        -- end

        -- Search outward if not found
        local node = start_node ---@type TSNode?
        if not inwards_only then
            while node ~= nil do
                if node:type() == type_ then
                    return node, type_
                end
                node = node:parent()
            end
        end
    end
    return nil
end

---Find the biggest contiguous subarray containing a given index which satisfies a predicate
---@param array table The array to search within.
---@param index integer The index to start the search from.
---@param predicate fun(element): boolean The predicate function to test each element.
---@return integer left Starting index of the subarray, or -1 if no subarray is found.
---@return integer right Ending index of the subarray, or -1 if no subarray is found.
function M.find_subarray(array, index, predicate)
    if index < 1 or index > #array then
        error 'Index out of bounds'
    end
    if not predicate(array[index]) then
        return -1, -1
    end

    local left, right = index, index
    for i = index, 1, -1 do
        if not predicate(array[i]) then
            break
        end
        left = i
    end
    for i = index, #array, 1 do
        if not predicate(array[i]) then
            break
        end
        right = i
    end
    return left, right
end

---Extract comment tokens used for specific
---@param node_type string Single-line or multiline comment
---@param ft string Filetype string
---@param rules Rules Comment parsing rules for supported filetypes
---@return string[][] multi Array of singleline tokens
---@return string[][] single Array of multiline tokens
function M.get_node_tokens(node_type, ft, rules)
    local ft_rules = rules[ft]
    local node_rules = ft_rules[node_type]

    local single, multi = {}, {}
    for _, rule in ipairs(node_rules) do
        if #rule == 2 then
            table.insert(multi, rule)
        else
            table.insert(single, rule)
        end
    end
    return multi, single
end

---Extract comment tokens used for specific
---@param ft string Filetype string
---@param rules Rules parsing rules for supported filetypes
function M.get_custom_nodes(ft, rules)
    local ft_rules = rules[ft]
    if ft_rules == nil then
        return nil
    end
    return vim.tbl_keys(ft_rules)
end

---Concatenates non-whitespace-only lines into a single string, separated by spaces.
---@param lines table: A array containing lines of text.
---@return string: A single string with non-whitespace-only lines concatenated, separated by spaces.
function M.concatenate_lines(lines)
    local com_text = ''
    for _, line in ipairs(lines) do
        if not M.is_whitespace_only(line) then
            com_text = com_text .. line .. ' '
        end
    end
    if #com_text > 0 then
        com_text = com_text:sub(1, -2) -- Remove the last character (trailing space)
    end
    return com_text
end

-- FIXME: UNUSED
---Strip raw comment lines from comment tokens and concatenate
---the comment body into a single string
---@param lines string[]
---@return string com_prefix Character/s denoting a string
---@return string com_string Comment string
local function concatenate_comment(lines)
    local comments = {}
    local com_char, com_prefix
    for _, line in ipairs(lines) do
        -- Lua pattern matching does not support backreferences, hence split into 2 matches here
        -- Find what char is used as comment token
        com_char = string.match(line, '^%s*.')
        -- Check if it's not repeated like lua's --- or js's //
        com_prefix = string.match(line, '^%s*(' .. com_char .. '*)')
        -- Cut comment token from the comment
        line = string.gsub(line, '^%s*' .. com_char .. '*%s*', '')
        -- Cut trailing whitespaces
        line = string.gsub(line, '%s*$', '')
        table.insert(comments, line)
    end
    return com_prefix, table.concat(comments, ' ')
end

-- FIXME: UNUSED
---Parse a comment string to identify whether it's single-line
---@param com_text string Comment raw string
---@return 'single'|'multi'|nil comment_type `nil` means text failed to match to a comment using known comment tokens
---@return string comment_body
---@return string|string[] comment_token Opening character/s denoting a comment
local function infer_singleline(com_text)
    -- NOTE: Fallback to language-agnostic `prefix_token` inferrence if `ft_syntax`
    -- is not provided or the function did not return up to this point
    local com_char, com_prefix
    -- Lua pattern matching does not support backreferences, hence split into 2 matches here
    -- Find what char is used as comment token
    com_char = string.match(com_text, '^%s*')
    -- Check if it's not repeated like lua's --- or js's //
    com_prefix = string.match(com_text, '^%s*(' .. com_char .. '*)')
    -- Cut comment token from the comment
    com_text = string.gsub(com_text, '^%s*' .. com_char .. '*%s*', '')
    -- Cut trailing whitespaces
    com_text = string.gsub(com_text, '%s*$', '')
    return 'single', 'wrong', com_prefix -- FIXME: WRRONG
end

return M
