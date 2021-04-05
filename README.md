# GenerateProperties.jl
Suite of macros to automatically generate getters &amp; setters for object properties, including corresponding `hasproperty` and `propertynames` methods.

Directly accessing properties of an object rather than defining an API can reduce namespace clutter (although one should definitely consider both approaches). Julia supports directly overriding default behavior of `getproperty` and `setproperty!`, but these methods are monolithic - i.e. you must differentiate between requested properties based on the property name. For large collections of virtual properties, this naturally separates properties' getters from their setters, reducing code clarity. These also do not add virtual properties to `hasproperty` and `propertynames` methods.

The `@generate_properties` macro provided by this library deals with all of these issues, albeit with some restrictions.

# Usage
GenerateProperties exposes three macros: `@generate_properties`, `@get`, and `@set`, where the latter two do not have any use outside the scope of a `@generate_properties` block.

The library's syntax is rather simple:

```julia
@generate_propertyes <type> begin
    @get <property> = <code_body>
    @set <property> = <code_body>
end
```

Where you may, of course, order `@get` and `@set` declarations arbitrarily. As mentioned before, the `@get` and `@set` macros only function in tandem with the `@generate_properties` macro. Outside of one such they simply return `nothing`.

The syntax is designed to be reminiscent of "function assignment" syntax of Vanilla Julia. For examples, see below.

Note that code other than `@get`/`@set` will be silently swallowed.

## Virtual Properties
*GenerateProperties* allows defining purely virtual properties. By example:

```julia
mutable struct MyStruct
    size::NTuple{2, Float64}
end

@generate_properties MyStruct begin
    @get width = self.size[1]
    @set width = self.size = (value, self.size[2])
    
    @get height = self.size[2]
    @set height = self.size = (self.size[1], value)
end

let inst = MyStruct((24, 25))
    inst.width  # 24
    inst.height # 25
    inst.size   # (24, 25)
    
    inst.width = 42
    inst.width # 42
    inst.size  # (42, 25)
    
    hasproperty(inst, :width)  # true
    hasproperty(inst, :height) # true
    hasproperty(inst, :size)   # true
end
```

Based on the enclosed `@get` and `@set` definitions, `@generate_property` automatically accumulates property names - both concrete fields and virtual properties - and automatically generates the corresponding property-related methods for your type.

`@get` and `@set` are designed to appear like property assignments - although they are really function bodies. Within *code_body*, one may refer to the current instance through the implicitly defined `self::<type>` argument. Within the *code_body* of a *setter*, one may access the implicitly defined `value` argument, which is the value to be assigned to the property.

## Field Getters & Setters
Because `self` bypasses `getproperty`/`setproperty!`, you may override concrete fields as well. In doing so, omitting either a getter or setter will retain default Vanilla behavior. For example:

```julia
struct MyStruct
    size::NTuple{2, Float64}
    dirty::Bool
end
MyStruct(size = (0, 0)) = MyStruct(size, false)

@generate_properties MyStruct begin
    @set size = (self.dirty = true; self.size = value)
end

let inst = MyStruct()
    inst.size  # (0, 0)
    inst.dirty # false
    
    inst.size = (24, 25)
    inst.size  # (24, 25)
    inst.dirty # true
end
```

# Library Restrictions
*GenerateProperties* does (currently) not support hybrid usage, i.e. manually defining `getproperty`/`setproperty!` while using `@generate_property`. You must commit to either approach.

Using `self` within a getter/setter bypasses `getproperty` & `setproperty!` and directly calls `getfield` and `setfield!` instead - otherwise this could cause a stack overflow.
