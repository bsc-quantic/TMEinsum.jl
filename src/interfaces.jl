"""
    ein"ij,jk -> ik"(A,B)

String macro interface which understands `numpy.einsum`'s notation.
Translates strings into `StaticEinCode`-structs that can be called to evaluate
an `einsum`.
To control evaluation order, use parentheses - instead of an `EinCode`,
a `NestedEinsum` is returned which evaluates the expression
according to parens.
The valid character ranges for index-labels are `a-z` and `α-ω`.

# example

```jldoctest; setup = :(using OMEinsum)
julia> a, b, c = rand(10,10), rand(10,10), rand(10,1);

julia> ein"ij,jk,kl -> il"(a,b,c) ≈ ein"(ij,jk),kl -> il"(a,b,c) ≈ a * b * c
true
```
"""
macro ein_str(s::AbstractString)
    ein(s)
end

function ein(s::AbstractString)
    s = replace(replace(s, "\n" => ""), " "=>"")
    m = match(r"([\(\)a-z,α-ω]*)->([a-zα-ω]*)", s)
    m === nothing && throw(ArgumentError("invalid einsum specification $s"))
    sixs, siy = m.captures
    if '(' in sixs
        return parse_nested(sixs, collect(siy))
    else
        iy  = Tuple(siy)
        ixs = Tuple(Tuple(ix) for ix in split(sixs,','))
        return StaticEinCode{Char, ixs, iy}()
    end
end

function (code::DynamicEinCode{LT})(@nospecialize(xs...); size_info=nothing) where LT
    size_dict = get_size_dict!(getixs(code), xs, size_info===nothing ? Dict{LT,Int}() : copy(size_info))
    einsum(code, xs, size_dict)
end

function (code::StaticEinCode{LT})(xs...; size_info=nothing) where LT
    size_dict = get_size_dict!(getixs(code), xs, size_info===nothing ? Dict{LT,Int}() : copy(size_info))
    einsum(code, xs, size_dict)
end

# 2us overheads if @nospecialize
@doc raw"
    get_size_dict!(ixs, xs, size_info)

return a dictionary that is used to get the size of an index-label
in the einsum-specification with input-indices `ixs` and tensors `xs` after
consistency within `ixs` and between `ixs` and `xs` has been verified.
"
@inline function get_size_dict!(ixs, xs, size_info::Dict{LT}) where LT
    if length(ixs) == 1
        get_size_dict_unary!(ixs[1], size(xs[1]), size_info)
    else
        get_size_dict_!(ixs, [collect(Int, size(x)) for x in xs], size_info)
    end
end

function get_size_dict_!(ixs, sizes::AbstractVector, size_info::Dict{LT}) where LT
    # check size of input tuples
    length(sizes)<1 && error("empty input tensors")
    length(ixs) != length(sizes) && throw(ArgumentError("$(length(sizes)) tensors labelled by $(length(ixs)) indices"))
    # check tensor orders
    @inbounds for i=1:length(sizes)
        ix, s = ixs[i], sizes[i]
        length(ix) == length(s) || throw(
            ArgumentError("indices $ix invalid for tensor with ndims = $(length(s))"))
        for j = 1:length(ix)
            k = ix[j]
            if haskey(size_info, k)
                s[j] == size_info[k] || throw(DimensionMismatch("$k = $(size_info[k]) or $(s[j]))?"))
            else
                size_info[k] = s[j]
            end
        end
    end
    return size_info
end
# to speed up unary operations
function get_size_dict_unary!(ix, s, size_info::Dict{LT}) where LT
    @inbounds for j = 1:length(ix)
        k = ix[j]
        if haskey(size_info, k)
            s[j] == size_info[k] || throw(DimensionMismatch("$k = $(size_info[k]) or $(s[j]))?"))
        else
            size_info[k] = s[j]
        end
    end
    return size_info
end

@inline function get_size_dict(ixs, xs, size_info=nothing)
    LT = foldl((a, b) -> promote_type(a, eltype(b)), ixs; init=Union{})
    return get_size_dict!(ixs, xs, size_info===nothing ? Dict{LT,Int}() : size_info)
end
@inline function get_size_dict(ixs::AbstractVector{<:AbstractVector{LT}}, xs, size_info=nothing) where LT
    return get_size_dict!(ixs, xs, size_info===nothing ? Dict{LT,Int}() : size_info)
end

using MacroTools
"""
    @ein A[i,k] := B[i,j] * C[j,k]     # A = B * C

Macro interface similar to that of other packages.

You may use numbers in place of letters for dummy indices, as in `@tensor`,
and need not name the output array. Thus `A = @ein [1,2] := B[1,ξ] * C[ξ,2]`
is equivalent to the above. This can also be written `A = ein"ij,jk -> ik"(B,C)`
using the numpy-style string macro.

# example

```jldoctest; setup = :(using OMEinsum)
julia> a, b = rand(2,2), rand(2,2);

julia> @ein c[i,k] := a[i,j] * b[j,k];

julia> c ≈ a * b
true

julia> c ≈ ein"ij,jk -> ik"(a,b)
true
```
"""
macro ein(exs...)
    _ein_macro(exs...)
end


primefix!(ind) = map!(i -> @capture(i, (j_)') ? Symbol(j, '′') : i, ind, ind)

function _ein_macro(ex; einsum=:einsum)
    @capture(ex, (left_ := right_)) || throw(ArgumentError("expected A[] := B[]... "))
    @capture(left, Z_[leftind__] | [leftind__] ) || throw(
        ArgumentError("can't understand LHS, expected A[i,j] etc."))
    if Z===nothing
        @gensym Z
    end
    primefix!(leftind)

    rightind, rightpairs = [], []
    @capture(right, *(factors__)) || (factors = Any[right])
    for fact in factors
        @capture(fact, A_[Aind__]) || return _nested_ein_macro(ex)
        primefix!(Aind)
        append!(rightind, Aind)
        push!(rightpairs, (A, Aind) )
    end
    unique!(rightind)
    isempty(setdiff(leftind, rightind)) || throw(
        ArgumentError("some indices appear only on the left"))

    lefttuple = Tuple(indexin(leftind, rightind))
    righttuples = [ Tuple(indexin(ind, rightind)) for (A, ind) in rightpairs ]
    rightnames = [ esc(A) for (A, ind) in rightpairs ]

    return :( $(esc(Z)) = $einsum( EinCode(($(righttuples...),), $lefttuple), ($(rightnames...),)) )
end

@doc raw"
    einsum(code::EinCode, xs, size_dict)
    einsum(rule, ixs, iy, xs, size_dict)

return the tensor that results from contracting the tensors `xs` according
to their indices `ixs` (`getixs(code)`), where all indices that do not appear in the output `iy` (`getiy(code)`) are
summed over.
The result is permuted according to `out`.

- `ixs` - tuple of tuples of index-labels of the input-tensors `xs`

- `iy` - tuple of index-labels of the output-tensor

- `xs` - tuple of tensors

- `size_dict` - a dictionary that maps index-labels to their sizes

# example

```jldoctest; setup = :(using OMEinsum)
julia> a, b = rand(2,2), rand(2,2);

julia> einsum(EinCode((('i','j'),('j','k')),('i','k')), (a, b)) ≈ a * b
true

julia> einsum(EinCode((('i','j'),('j','k')),('k','i')), (a, b)) ≈ permutedims(a * b, (2,1))
true
```
"
@generated function einsum!(code::StaticEinCode{LT, ixs, iy}, xs::Tuple, res::AbstractArray, size_dict::Dict{LT}) where {LT, ixs, iy}
    rule = match_rule(ixs, iy)
    :(einsum!($rule, $ixs, $iy, xs, res, size_dict))
end

function einsum!(code::DynamicEinCode, @nospecialize(xs::Tuple), res::AbstractArray, size_dict::Dict)
    rule = match_rule(getixs(code), getiy(code))
    einsum!(rule, getixs(code), getiy(code), xs, res, size_dict)
end

# the fallback
function einsum!(::DefaultRule, ixs, iy, xs::Tuple, res::AbstractArray, size_dict)
    @debug "DefaultRule loop_einsum" ixs => iy size.(xs)
    loop_einsum!(EinCode(ixs, iy), (xs...,), res, size_dict)
end


## non-inplace einsum
function einsum(code::AbstractEinsum, @nospecialize(xs::Tuple), size_dict::Dict)
    res = get_output_array(xs, map(y->size_dict[y],getiyv(code)); has_repeated_indices=false)
    einsum!(code, xs, res, size_dict)
end

function einsum(code::EinCode, @nospecialize(xs::Tuple))
    einsum(code, xs, get_size_dict!(getixs(code), xs, Dict{labeltype(code),Int}()))
end