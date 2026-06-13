---@meta

-- Missing luassert aliases not covered by built-in types.

-- assert.has.errors(fn) / assert.has_no.errors(fn)
-- internal.has = internal, so assert.has.errors = internal.errors
---@class luassert.internal
---@field errors fun(callback:function, error?:string)

-- assert.spy(s).was_called(n)  (underscore alias for .was.called)
-- assert.spy(s).was_called_with(...)  (underscore alias for .was.called_with)
---@class luassert.spy.assert
---@field was_called fun(times?:integer)
---@field was_called_with fun(...:any)
