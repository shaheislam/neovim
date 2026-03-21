# Test: Treesitter-aware gw/gq

## Test 1: Lua code block with long comments

Place cursor on the long comment line below and press `gqip` to reformat.
The `--` comment leader should be preserved correctly:

```lua
-- This is a very long comment that describes something important about the implementation and should be wrapped at textwidth while preserving the Lua comment leader correctly without mangling it into markdown comment style
local function hello()
  return "world"
end
```

## Test 2: Python code block with long comments

Same test but with `#` comment leader:

```python
# This is a very long comment in Python that describes the algorithm complexity and should be wrapped correctly preserving the hash comment leader instead of using markdown comment style which would break things
def hello():
    return "world"
```

## Test 3: Go code block with long comments

```go
// This is a very long comment in Go that describes the function behavior and edge cases and should be wrapped correctly preserving the double-slash comment leader when using gq inside this markdown code block
func Hello() string {
    return "world"
}
```

Without treesitter-aware gw/gq, reformatting inside these code blocks
uses markdown's comment settings, which mangles the language-specific
comment leaders (`--`, `#`, `//`).
