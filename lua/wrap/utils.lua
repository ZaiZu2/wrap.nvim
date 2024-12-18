M = {}
local temp = require 'utils' -- TODO: Temporary, delete
local p = temp.pprint

---Escape REGEX magic characters
---@param str string
---@return string str Escaped string
function M.escape(str)
    local escaped, _ = string.gsub(str, '[.*+?^$()[%%-]', '%%%0')
    return escaped
end

---Check if the string consist of whitespaces only
---@param str string
---@return boolean
function M.is_whitespace_only(str)
    return not not string.match(str, '^%s*$')
end

---Traverse TS tree upwards in search of a closest node of a provided type
---@param node TSNode|nil
---@param type string TSNode type to search for
---@return TSNode|nil
function M.find_node(node, type)
    while node ~= nil do
        if node:type() == type then
            return node
        end
        node = node:parent()
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
    p { array = array, index = index, result = not predicate(array[index]) }
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

---Extract comment symbols used for specific
---@param com_type 'single'|'multi' Single-line or multiline comment
---@param ft string Filetype string
---@param rules table Comment parsing rules for supported filetypes
---@return string[]|nil symbols Array of symbols if available
function M.get_comment_symbol(com_type, ft, rules)
    local ft_rules = rules[ft]
    if ft_rules == nil then
        return nil
    end
    return ft_rules[com_type]
end

-- FIXME: UNUSED
---Strip raw comment lines from comment symbols and concatenate
---the comment body into a single string
---@param lines string[]
---@return string com_prefix Character/s denoting a string
---@return string com_string Comment string
local function concatenate_comment(lines)
    local comments = {}
    local com_char, com_prefix
    for _, line in ipairs(lines) do
        -- Lua pattern matching does not support backreferences, hence split into 2 matches here
        -- Find what char is used as comment symbol
        com_char = string.match(line, '^%s*.')
        -- Check if it's not repeated like lua's --- or js's //
        com_prefix = string.match(line, '^%s*(' .. com_char .. '*)')
        -- Cut comment symbol from the comment
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
---@return 'single'|'multi'|nil comment_type `nil` means text failed to match to a comment using known comment symbols
---@return string comment_body
---@return string|string[] comment_symbol Opening character/s denoting a comment
local function infer_singleline(com_text)
    -- NOTE: Fallback to language-agnostic `prefix_symbol` inferrence if `ft_syntax`
    -- is not provided or the function did not return up to this point
    local com_char, com_prefix
    -- Lua pattern matching does not support backreferences, hence split into 2 matches here
    -- Find what char is used as comment symbol
    com_char = string.match(com_text, '^%s*')
    -- Check if it's not repeated like lua's --- or js's //
    com_prefix = string.match(com_text, '^%s*(' .. com_char .. '*)')
    -- Cut comment symbol from the comment
    com_text = string.gsub(com_text, '^%s*' .. com_char .. '*%s*', '')
    -- Cut trailing whitespaces
    com_text = string.gsub(com_text, '%s*$', '')
    return 'single', 'wrong', com_prefix -- FIXME: WRRONG
end

return M
