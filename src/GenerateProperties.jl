######################################################################
# Suite of macros to automatically generate getters and setters for
# object properties along with the accompanying `hasproperty` and
# `propertynames` specializations.
# -----
# Licensed under MIT License
module GenerateProperties

const Optional{T} = Union{T, Nothing}
const GetterSetterBody = Tuple{Optional{LineNumberNode}, Expr}

struct StructProp{S, F} end
struct StructField{S, F} end

assign(inst, field::Symbol, value) = assign(StructProp{typeof(inst), field}, inst, value)
assign( ::Type{StructProp{ S, F}}, inst::S, value) where {S, F} = assign(StructField{S, F}, inst, value)
assign(T::Type{StructField{S, F}}, inst::S, value) where {S, F} = assign(getfieldtype(T), inst, F, value)
assign(::Type{T},  inst, field::Symbol, value)     where {T}                      = setfield!(inst, field, convert(T, value))
assign(::Type{T1}, inst, field::Symbol, value::T2) where {T1, T2<:T1}             = setfield!(inst, field, value)
assign(::Type{T1}, inst, field::Symbol, value::T2) where {T1<:Number, T2<:Number} = setfield!(inst, field, T1(value))

retrieve(inst, field::Symbol) = retrieve(StructProp{typeof(inst), field}, inst)
retrieve(::Type{StructProp{ S, F}}, inst::S) where {S, F} = retrieve(StructField{S, F}, inst)
retrieve(::Type{StructField{S, F}}, inst::S) where {S, F} = getfield(inst, F)

getparambody(x) = x
getparambody(unionall::UnionAll) = getparambody(unionall.body)

getfieldtype(S::Type, F::Symbol) = getfieldtype(StructField{S, F})
@generated function getfieldtype(::Type{StructField{S, F}}) where {S, F}
    @assert !isa(S, UnionAll) "Cannot reliably use getfieldtype with UnionAll"
    
    idx = findfirst(field->field==F, fieldnames(S))
    @assert idx !== nothing "Field $F not found in type $S"
    
    T = S.types[idx]
    :($T)
end

export @generate_properties
macro generate_properties(T, block)
    if !isa(block, Expr) || block.head != :block
        throw(ArgumentError("Second argument to @generate_properties must be a block"))
    end
    
    result = Expr(:block)
    props  = Set{Symbol}()
    symget = Symbol("@get")
    symset = Symbol("@set")
    symeq  = Symbol("=")
    
    lastlinenumber = nothing
    for expr ∈ block.args
        if isa(expr, LineNumberNode)
            lastlinenumber = expr
        else
            if expr.head != :macrocall || expr.args[1] ∉ (symget, symset)
                throw(ArgumentError("Every line must be a call to either @get or @set"))
            end
            
            args = filterlinenumbers(expr.args)
            if args[2].head != symeq throw(ArgumentError("Getter/Setter not an assignment")) end
            prop, body = filterlinenumbers(args[2].args)
            body = replace_self(T, body)
            push!(props, prop)
            
            if expr.args[1] == symget
                push!(result.args, generate_getter(T, prop, lastlinenumber, body))
            elseif expr.args[1] == symset
                push!(result.args, generate_setter(T, prop, lastlinenumber, body))
            end
            
            lastlinenumber = nothing
        end
    end
    
    # Generate propertynames
    push!(result.args, quote
        @generated function Base.propertynames(::$T)
            res = tuple(union($props, fieldnames($T))...)
            :($res)
        end
    end)
    
    push!(result.args, :(Base.getproperty(self::$T, prop::Symbol) = GenerateProperties.retrieve(self, prop)))
    push!(result.args, :(Base.setproperty!(self::$T, prop::Symbol, value) = GenerateProperties.assign(self, prop, value)))
    
    esc(result)
end

export @get, @set
macro get(args...) end
macro set(args...) end

filterlinenumbers(exprs) = filter(expr->!isa(expr, LineNumberNode), exprs)

replace_self(_, expr) = expr
function replace_self(T::Union{Symbol, Expr}, expr::Expr)
    @assert isa(T, Symbol) || T.head == :curly
    if expr.head == :(=)
        lhs, rhs = expr.args
        
        if isa(lhs, Expr) && lhs.head == :. && lhs.args[1] == :self
            prop = lhs.args[2]::QuoteNode
            expr = :(GenerateProperties.assign(self, $rhs))
            insert!(expr.args, 2, structfieldexpr(prop))
        end
    elseif expr.head == :.
        if expr.args[1] == :self
            prop = expr.args[2]::QuoteNode
            expr = :(GenerateProperties.retrieve(self))
            insert!(expr.args, 2, structfieldexpr(prop))
        end
    end
    expr.args = map(sub->replace_self(T, sub), expr.args)
    expr
end

function generate_getter(T, prop::Symbol, linenumber::Optional{LineNumberNode}, body)
    block = Expr(:block)
    if linenumber !== nothing push!(block.args, linenumber) end
    push!(block.args, body)
    
    fnexpr = :(GenerateProperties.retrieve(self::$T) = $block)
    insert!(fnexpr.args[1].args, 2, argsubtypeexpr(structpropexpr(T, prop)))
    fnexpr
end

function generate_setter(T, prop::Symbol, linenumber::Optional{LineNumberNode}, body)
    block = Expr(:block)
    if linenumber !== nothing push!(block.args, linenumber) end
    push!(block.args, body)
    
    fnexpr = :(GenerateProperties.assign(self::$T, value) = $block)
    insert!(fnexpr.args[1].args, 2, argsubtypeexpr(structpropexpr(T, prop)))
    fnexpr
end

structpropexpr(T, prop::QuoteNode) = Expr(:curly, :(GenerateProperties.StructProp), :(<:$T), prop)
structpropexpr(T, prop::Symbol)    = structpropexpr(T, QuoteNode(prop))
structfieldexpr(prop::QuoteNode) = Expr(:curly, :(GenerateProperties.StructField), :(typeof(self)), prop)
structfieldexpr(prop::Symbol)    = structfieldexpr(QuoteNode(prop))

function argtypeexpr(type::Expr)
    Expr(:(::), Expr(:curly, :Type, type))
end

function argsubtypeexpr(type::Expr)
    Expr(:(::), Expr(:curly, :Type, Expr(:<:, type)))
end

end # module GenerateProperties
