"""
    asarray(x[, parent::AbstractArray]) -> AbstactArray

Return a 0-dimensional array with item `x`, otherwise, do nothing.
If a `parent` is supplied, it will try to match the parent array type.
"""
asarray(x) = fill(x, ())
asarray(x::AbstractArray) = x
asarray(x, arr::AbstractArray) = fill(x, ())
asarray(x::AbstractArray, y::Array) = x
asscalar(x) = x
asscalar(x::AbstractArray) = x[]
_collect(x) = collect(x)
_collect(x::Vector) = x
_collect(::Type{T}, x::Vector{T}) where T = x
_collect(::Type{T}, x) where T = collect(T, x)
_insertat(lst::Tuple, i, item) = TupleTools.insertat(lst, i, (item,))
_insertat(lst::AbstractVector, i, item) = (lst=copy(lst); lst[i]=item; lst)

"""
    nopermute(ix,iy)

check that all values in `iy` that are also in `ix` have the same relative order,

# example

```jldoctest; setup = :(using OMEinsum)
julia> using OMEinsum: nopermute

julia> nopermute((1,2,3),(1,2))
true

julia> nopermute((1,2,3),(2,1))
false
```
e.g. `nopermute((1,2,3),(1,2))` is true while `nopermute((1,2,3),(2,1))` is false
"""
function nopermute(ix::NTuple, iy::NTuple)
    i, j, jold = 1, 1, 0
    # find each element of iy in ix and check that the order is the same
    for i in 1:length(iy)
        j = findfirst(==(iy[i]), ix)
        (j === nothing || j <= jold) && return false
        jold = j
    end
    return true
end

"""
    allunique(ix::Tuple)

return true if all elements of `ix` appear only once in `ix`.

# example

```jldoctest; setup = :(using OMEinsum)
julia> using OMEinsum: allunique

julia> allunique((1,2,3,4))
true

julia> allunique((1,2,3,1))
false
```
"""
allunique(ix) = all(i -> count(==(i), ix) == 1, ix)
_unique(::Type{T}, x::NTuple{N,T}) where {N,T} = unique!(collect(T, x))
_unique(::Type{T}, x::Vector{T}) where T = unique(x)

function align_eltypes(xs::AbstractArray...)
    T = promote_type(eltype.(xs)...)
    return map(x->eltype(x)==T ? x : T.(x), xs)
end

function align_eltypes(xs::AbstractArray{T}...) where T
    xs
end

"""
    tensorpermute(A, perm)

`permutedims(A, perm)` with grouped dimensions.
"""
function tensorpermute(A::AbstractArray{T,N}, perm) where {T, N}
    @assert N == length(perm) && all(p->1<=p<=N, perm)
    N == 0 && return copy(A)
    # group `perm`s
    permshape = ntuple(i->size(A, @inbounds perm[i]), N)
    newshape_slots = fill(-1, N)
    dk = 1  # the size of dimension-batch
    @inbounds begin
        permk = perm[1]
        newperm = [permk]
        newshape_slots[permk] = size(A, permk)
    end
    @inbounds for i=2:N
        permi = perm[i]
        if permi == permk + dk  # same group
            newshape_slots[permk] *= size(A, permi)
            dk += 1
        else
            permk = permi
            newshape_slots[permk] = size(A, permi)
            push!(newperm, permk)
            dk = 1
        end
    end
    newshape = filter(!=(-1), newshape_slots)
    newperm = sortperm(sortperm(newperm))
    A_ = reshape(A, newshape...)
    A__ = permutedims(A_, newperm)
    return reshape(A__, permshape...)
end

# reload this function for GPU support!
function _batched_gemm(C1::Char, C2::Char, A::StridedArray{T,3}, B::StridedArray{T2,3}) where {T<:BlasFloat, T2<:BlasFloat}
    batched_gemm(C1, C2, A, B)
end

function _batched_gemm(C1::Char, C2::Char, A::AbstractArray{T,3}, B::AbstractArray{T2,3}) where {T<:BlasFloat, T2<:BlasFloat}
    batched_gemm(C1, C2, Array(A), Array(B))
end

function _batched_gemm(C1::Char, C2::Char, A::AbstractArray{T,3}, B::AbstractArray{T2,3}) where {T, T2}
    @assert size(A, 3) == size(B, 3) "batch dimension mismatch, got $(size(A,3)) and $(size(B,3))"
    @assert C1 === 'N' || C1 === 'T'
    @assert C2 === 'N' || C2 === 'T'
    L = size(A, 3)
    C = similar(A, promote_type(T,T2), C1==='N' ? size(A,1) : size(A,2), C2==='N' ? size(B,2) : size(B,1), L)
    for l = 1:L
        a = C1 === 'T' ? transpose(view(A,:,:,l)) : view(A,:,:,l)
        b = C2 === 'T' ? transpose(view(B,:,:,l)) : view(B,:,:,l)
        mul!(view(C,:,:,l), a, b)
    end
    return C
end

# macro addmul!(a, y, b, xs...)
#     added = :(Ref(b))
#     for x in xs
#         added = :($added .* $x)
#     end
#     yeval = gensym("y")
#     quote
#         $yeval = $y
#         if iszero($b)   # no need to multiply
#             $lmul!($a, $yeval)
#         elseif iszero($a)  # empty y
#             $yeval .= $added
#         elseif isone($a)
#             $yeval .+= $added
#         else  # a != 1, a != 0, b != 0
#             $yeval .= Ref($a) .* $yeval .+ $added
#         end
#         $yeval
#     end |> esc
# end

macro addmul!(ex)
    @match ex begin
        :($y .= $a .* $y .+ $b .* $xs) => begin
            quote
                if iszero($b)   # no need to multiply
                    $lmul!($a, $y)
                elseif iszero($a)  # empty y
                    $y .= Ref($b) .* $xs
                elseif isone($a)
                    $y .+= Ref($b) .* $xs
                else  # a != 1, a != 0, b != 0
                    $y .= Ref($a) .* $y .+ Ref($b) .* $xs
                end
                $y
            end |> esc
        end
    end
end