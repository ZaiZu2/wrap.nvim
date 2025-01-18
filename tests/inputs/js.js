// TEST CASE: 1
// FUNCTION: Wrap comment
// STATE: n:1:12
// DESCRIPTION: Simple wrap of multiple lines into one
// INPUT START
// Single-line comments
// which are of various length
// but consistently placed and spaced
// INPUT END
// OUTPUT START
// Single-line comments which are of various length but consistently placed and spaced
// OUTPUT END

// -----------------------------------------
// TEST CASE: 2
// FUNCTION: Wrap comment
// STATE: n:1:12
// DESCRIPTION: Adjust comment test position relative to the comment symbol
// INPUT START
//    Single-line comment with leading spaces
// INPUT END
// OUTPUT START
// Single-line comment with leading spaces
// OUTPUT END

// -----------------------------------------
// TEST CASE: 3
// FUNCTION: Wrap comment
// STATE: n:1:26
// DESCRIPTION: Simple wrap of multiple lines into one
// INPUT START
    // Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
  // incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
// exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure
// INPUT END
// OUTPUT START
    // Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
    // incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
    // exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure
// OUTPUT END
// -----------------------------------------
// TEST CASE: 4
// FUNCTION: Wrap comment
// STATE: n:2:30
// DESCRIPTION: Simple wrap of multiple lines into one
// INPUT START
    // Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
  // incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
// exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure
// INPUT END
// OUTPUT START
  // Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
  // incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
  // exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure
// OUTPUT END
// -----------------------------------------
// TEST CASE: 5
// FUNCTION: Wrap comment
// STATE: n:3:55
// DESCRIPTION: Simple wrap of multiple lines into one
// INPUT START
    // Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
  // incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
// exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure
// INPUT END
// OUTPUT START
// Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt
// ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation
// ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure
// OUTPUT END


// TEST CASE: 2
// FUNCTION: Wrap block
// STATE: n:1:12
// DESCRIPTION: Hurr durr purr murr

// INPUT START
// Single-line comments
// which are of various length
// but consistently placed and spaced
// INPUT END

// OUTPUT START
// Single-line comments which are of various length but consistently placed and spaced
// OUTPUT END

// -----------------------------------------
// TEST UNUSED_CASE: 3
// FUNCTION: Wrap block
// STATE: v:1:12:2:12
// DESCRIPTION: Hurr durr purr murr

// INPUT START
// Single-line comments
// which are of various length
// but consistently placed and spaced
// INPUT END

// OUTPUT START
// Single-line comments which are of various length but consistently placed and spaced
// OUTPUT END
