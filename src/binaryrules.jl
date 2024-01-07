# binary operations that can not be simplified by a unitary operations
struct SimpleBinaryRule{ix1,ix2,iy} <: EinRule{2} end
function SimpleBinaryRule(code::EinCode)
    ixs, iy = getixs(code), getiy(code)
    @assert length(ixs)==2 "fail to construct simple binary rule from $code"
    SimpleBinaryRule{ixs[1], ixs[2], iy}()
end
SimpleBinaryRule(ix1, ix2, iy) = SimpleBinaryRule{ix1, ix2, iy}()

@inline function _add_patch(::SimpleBinaryRule{ix1,ix2,iy}) where {ix1,ix2,iy}
    SimpleBinaryRule{(ix1...,'l'), (ix2...,'l'), (iy...,'l')}()
end
@inline _add_patch(::DefaultRule) = DefaultRule()

function match_rule_binary(ix1, ix2, iy)
    Nx1, Nx2, Ny = length(ix1), length(ix2), length(iy)
    if !_isunique(ix1) || !_isunique(ix2) || !_isunique(iy)
        DefaultRule()
    elseif (Nx1 + Nx2 + Ny) % 2 == 0 # no batch
        _match_simple2(ix1,ix2,iy,Nx1,Nx2,Ny)
    elseif Nx1>0 && Nx2>0 && Ny>0 && ix1[Nx1]==ix2[Nx2]==iy[Ny]
        rule = _match_simple2(ix1,ix2,iy,Nx1-1,Nx2-1,Ny-1)
        _add_patch(rule)
    else
        DefaultRule()
    end
end
@inline function _isunique(ix)
    if length(ix) <= 1
        return true
    elseif length(ix) == 2
        return @inbounds ix[1] != ix[2]
    elseif length(ix) == 3
        @inbounds a, b, c = ix
        return a != c && a != c && a != b
    else  # to default rules
        return false
    end
end

function _match_simple2(ix1, ix2, iy, Nx1, Nx2, Ny)
    if Nx1==0
        if (Ny==Nx2==0)
            return SimpleBinaryRule((), (), ())
        elseif (Ny==Nx2==1 && ix2[1] == iy[1])
            return SimpleBinaryRule((), ('k',), ('k',))
        end
    elseif Nx1==1
        if (Nx2==0 && Ny==1 && iy[1]==ix1[1])
            return SimpleBinaryRule(('i',), (), ('i',))
        elseif (Nx2==1 && Ny==0 && ix1[1]==ix2[1])
            return SimpleBinaryRule(('j',), ('j',), ())
        elseif Nx2==1 && Ny==2
            if (iy[1]==ix1[1] && iy[2]==ix2[1])
                return SimpleBinaryRule(('i',), ('k',), ('i','k'))
            elseif iy[1]==ix2[1] && iy[2]==ix1[1]
                return SimpleBinaryRule(('i',), ('k',), ('k','i'))
            end
        elseif Nx2==2 && Ny==1
            if ix2[1]==ix1[1] && ix2[2]==iy[1]
                return SimpleBinaryRule(('j',), ('j','k'), ('k',))
            elseif ix2[1]==iy[1] && ix2[2]==ix1[1]
                return SimpleBinaryRule(('j',), ('k','j'), ('k',))
            end
        end
    elseif Nx1==2
        if Nx2==1 && Ny==1
            if ix1[1]==ix2[1] && ix1[2]==iy[1]
                return SimpleBinaryRule(('j','i'), ('j',), ('i',))
            elseif ix1[1]==iy[1] && ix1[2]==ix2[1]
                return SimpleBinaryRule(('i','j'), ('j',), ('i',))
            end
        elseif (Nx2==2 && Ny==2)
            if ix1[1]==ix2[1] && ix1[2]==iy[1] && ix2[2]==iy[2]
                return SimpleBinaryRule(('j','i'), ('j','k'), ('i','k'))
            elseif ix1[1]==ix2[2] && ix1[2]==iy[1] && ix2[1]==iy[2]
                return SimpleBinaryRule(('j','i'), ('k','j'), ('i','k'))
            elseif ix1[1]==ix2[1] && ix1[2]==iy[2] && ix2[2]==iy[1]
                return SimpleBinaryRule(('j','i'), ('j','k'), ('k','i'))
            elseif ix1[1]==ix2[2] && ix1[2]==iy[2] && ix2[1]==iy[1]
                return SimpleBinaryRule(('j','i'), ('k','j'), ('k','i'))
            elseif ix1[2]==ix2[1] && ix1[1]==iy[1] && ix2[2]==iy[2]
                return SimpleBinaryRule(('i','j'), ('j','k'), ('i','k'))
            elseif ix1[2]==ix2[2] && ix1[1]==iy[1] && ix2[1]==iy[2]
                return SimpleBinaryRule(('i','j'), ('k','j'), ('i','k'))
            elseif ix1[2]==ix2[1] && ix1[1]==iy[2] && ix2[2]==iy[1]
                return SimpleBinaryRule(('i','j'), ('j','k'), ('k','i'))
            elseif ix1[2]==ix2[2] && ix1[1]==iy[2] && ix2[1]==iy[1]
                return SimpleBinaryRule(('i','j'), ('k','j'), ('k','i'))
            end
        end
    end
    return DefaultRule()
end

function einsum!(rule::SimpleBinaryRule, ixs, iy, xs, y, sx, sy, size_dict)
    @debug rule size.(xs)
    binary_einsum!(rule, xs..., y, sx, sy)
end
# Code is a binary representation of `(O1,I,O2,B)`.
# Because the time complexity of `GEMM` and `BatchedGEMM` are higher than space complexity, we allow `permutedims`.
# We reduce the contraction to these basic forms through `permutedims` and reshape,
# because we assume most using cases have both inner and outer degrees on freedom.

# ,-> : 000
# S = 1
# T = 1
function binary_einsum!(::SimpleBinaryRule{(),(), ()}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * x1 * x2
end

# i,->i : 100
# S = N
# T = N
function binary_einsum!(::SimpleBinaryRule{('i',),(), ('i',)}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * x1 * Ref(asscalar(x2))
end

# j,j-> : 010
# S = N
# T = N
function binary_einsum!(::SimpleBinaryRule{('j',), ('j',), ()}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * Ref(transpose(x1) * x2)
end

# ,k->k : 001
# S = N
# T = N
@inline function binary_einsum!(::SimpleBinaryRule{(), ('k',), ('k',)}, x1, x2, y, sx, sy)
    binary_einsum!(SimpleBinaryRule{('i',),(),('i',)}(), x2, x1, y, sx, sy)
end

# j,jk->k : 011
# S = N^2
# T = N^2
function binary_einsum!(::SimpleBinaryRule{('j',), ('j','k'), ('k',)}, x1, x2, y, sx, sy)
    mul!(y, transpose(x2), x1, sx, sy)
end
function binary_einsum!(::SimpleBinaryRule{('j',), ('k','j'), ('k',)}, x1, x2, y, sx, sy)
    mul!(y, x2, x1, sx, sy)
end

# ij,j->i : 110
# S = N^2
# T = N^2
@inline function binary_einsum!(::SimpleBinaryRule{('i','j'),('j',), ('i',)}, x1, x2, y, sx, sy)
    mul!(y, x1, x2, sx, sy)
end
@inline function binary_einsum!(::SimpleBinaryRule{('j','i'),('j',), ('i',)}, x1, x2, y, sx, sy)
    mul!(y, transpose(x1), x2, sx, sy)
end

# i,k->ik : 101
# S = N^2
# T = N^2
function binary_einsum!(::SimpleBinaryRule{('i',), ('k',), ('i','k')}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * x1 * transpose(x2)
end
@inline function binary_einsum!(::SimpleBinaryRule{('i',), ('k',),('k','i')}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * transpose(x1) * x2
end

# 000
function binary_einsum!(::SimpleBinaryRule{('l',),('l',), ('l',)}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * x1 * x2
end

# 100
function binary_einsum!(::SimpleBinaryRule{('i','l'),('l',), ('i','l')}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * x1 * transpose(x2)
end

# 001
@inline function binary_einsum!(::SimpleBinaryRule{('l',), ('k','l'), ('k','l')}, x1, x2, y, sx, sy)
    binary_einsum!(SimpleBinaryRule{('i','l'),('l',),('i','l')}(), x2, x1, y, sx, sy)
end

# 010
function binary_einsum!(::SimpleBinaryRule{('j','l'), ('j','l'), ('l',)}, x1, x2, y, sx, sy)
    @addmul! sy * y + sx * dropdims(mapreduce(*, +, x1, x2; dims=1); dims=1)
end

# 101
function binary_einsum!(::SimpleBinaryRule{('i','l'), ('k','l'), ('i','k','l')}, x1, x2, y::AbstractArray, sx, sy)
    _batched_gemm!('N', 'N', sx, reshape(x1, size(x1, 1), 1, size(x1, 2)), reshape(x2, 1, size(x2, 1), size(x2, 2)), sy, y)
end
@inline function binary_einsum!(::SimpleBinaryRule{('i','l'), ('k','l'), ('k','i','l')}, x1, x2, y::AbstractArray, sx, sy)
    _batched_gemm!('N', 'N', sx, reshape(x2, size(x2, 1), 1, size(x2, 2)), reshape(x1, 1, size(x1, 1), size(x1, 2)), sy, y)
end

# 011
function binary_einsum!(::SimpleBinaryRule{('j','l'), ('j','k','l'), ('k','l')}, x1, x2, y::AbstractArray, sx, sy)
    _batched_gemm!('N', 'N', sx, reshape(x1, 1, size(x1,1), size(x1,2)), x2, sy, reshape(y, 1, size(y,1), size(y,2)))
    y
end
function binary_einsum!(::SimpleBinaryRule{('j','l'), ('k','j','l'), ('k','l')}, x1, x2, y::AbstractArray, sx, sy)
    _batched_gemm!('N', 'T', sx, reshape(x1, 1, size(x1,1), size(x1,2)), x2, sy, reshape(y, 1, size(y,1), size(y,2)))
    y
end

# 110
function binary_einsum!(::SimpleBinaryRule{('i','j','l'), ('j','l'), ('i','l')}, x1, x2, y::AbstractArray, sx, sy)
    _batched_gemm!('N', 'N', sx, x1, reshape(x2, size(x2,1), 1, size(x2,2)), sy, reshape(y, size(y,1), 1, size(y,2)))
    y
end
function binary_einsum!(::SimpleBinaryRule{('j','i','l'), ('j','l'), ('i','l')}, x1, x2, y::AbstractArray, sx, sy)
    _batched_gemm!('T', 'N', sx, x1, reshape(x2, size(x2,1), 1, size(x2,2)), sy, reshape(y, size(y,1), 1, size(y,2)))
    y
end

# ij,jk->ik : 111
# S = N^2
# T = N^3
for (i1, X1) in enumerate([('i', 'j'), ('j', 'i')])
    for (i2, X2) in enumerate([('j', 'k'), ('k', 'j')])
        for (i3, X3) in enumerate([('i', 'k'), ('k', 'i')])
            A1 = i1==i3 ? :(x1) : :(transpose(x1))
            A2 = i2==i3 ? :(x2) : :(transpose(x2))
            @eval function binary_einsum!(::SimpleBinaryRule{$X1,$X2, $X3}, x1, x2, y::AbstractArray{T}, sx, sy) where T
                $(i3==1 ? :(mul!($A1, $A2, y, sx, sy)) : :(mul!($A2, $A1, y, sx, sy)))
            end
            X1B = (X1...,'l')
            X2B = (X2...,'l')
            X3B = (X3...,'l')
            C1 = i1==i3 ? 'N' : 'T'
            C2 = i2==i3 ? 'N' : 'T'
            @eval function binary_einsum!(::SimpleBinaryRule{$X1B,$X2B,$X3B}, x1, x2, y::AbstractArray{T}, sx, sy) where T
                $(i3==1 ? :(_batched_gemm!($C1, $C2, sx, x1, x2, sy, y)) : :(_batched_gemm!($C2, $C1, sx, x2, x1, sy, y)))
            end
        end
    end
end

# there are too many combination in the binary case, so nospecialize
function einsum!(ixs, iy, @nospecialize(xs::NTuple{2, Any}), @nospecialize(y), size_dict::Dict{LT}) where LT
    @debug "DefaultRule binary" ixs => iy size.(xs)
    ix1, ix2 = ixs
    x1, x2 = xs
    c1, c2, cy, s1, s2, i1, i2, iyb = analyze_binary(_collect(LT,ix1), _collect(LT,ix2), _collect(LT,iy), size_dict)
    rule = SimpleBinaryRule{(i1...,), (i2...,), (iyb...,)}()
    x1 = simplify_unary(_collect(LT,ix1), c1, x1, size_dict)
    x2 = simplify_unary(_collect(LT,ix2), c2, x2, size_dict)
    x1_ = reshape(x1, s1...)
    x2_ = reshape(x2, s2...)
    @debug rule size.((x1_, x2_))
    y_ = reshape(einsum(rule, (x1_, x2_)), [size_dict[x] for x in cy]...)
    y .= expand_unary(cy, _collect(LT,iy), y_, size_dict)
    return y
end

function simplify_unary(ix::Vector{T}, iy::Vector{T}, x, size_dict::Dict{T}) where T
    if ix == iy
        return x
    elseif length(ix) == length(iy) # permutation
        return einsum(Permutedims(), (ix,), iy, (x,), size_dict)
    else
        # diag
        ix_ = unique(ix)
        x_ = length(ix_) != length(ix) ? einsum(Diag(), (ix,), ix_, (x,), size_dict) : x
        # sum
        if length(ix_) != length(iy)
            return einsum(Sum(), (ix_,), iy, (x_,), size_dict)
        elseif ix_ != iy
            return einsum(Permutedims(), (ix_,), iy, (x_,), size_dict)
        else
            return x_
        end
    end
end

function expand_unary(ix::Vector{T}, iy::Vector{T}, x::AbstractArray, size_dict::Dict{T}) where T
    iy_b = unique(iy)
    iy_a = filter(i->i ∈ ix, iy_b)
    y_a = if ix != iy_a
        einsum(Permutedims(), (ix,), iy_a, (x,), size_dict)
    else
        x
    end
    # repeat
    y_b = length(iy_a) != length(iy_b) ? einsum(Repeat(), (iy_a,), iy_b, (y_a,), size_dict) : y_a
    # duplicate
    length(iy_b) != length(iy) ? einsum(Duplicate(), (iy_b,), iy, (y_b,), size_dict) : y_b
end

"""
Get the expected labels.
"""
function analyze_binary(ix1::Vector{T}, ix2::Vector{T}, iy::Vector{T}, size_dict::Dict{T,Int}) where T
    ix_inner, ix1_outer, ix2_outer, batch = _analyze_binary_input(ix1, ix2, iy)
    c1 = vcat(ix1_outer, ix_inner, batch)
    c2 = vcat(ix_inner, ix2_outer, batch)
    cy = vcat(ix1_outer, ix2_outer, batch)
    si = prod(map(x->size_dict[x], ix1_outer))
    sj = prod(map(x->size_dict[x], ix_inner))
    sk = prod(map(x->size_dict[x], ix2_outer))
    sl = prod(map(x->size_dict[x], batch))
    has_i = !isempty(ix1_outer)
    has_j = !isempty(ix_inner)
    has_k = !isempty(ix2_outer)
    has_l = !isempty(batch)
    i1 = Char[]
    i2 = Char[]
    iyb = Char[]
    s1 = Int[]
    s2 = Int[]
    if has_i
        push!(i1, 'i')
        push!(iyb, 'i')
        push!(s1, si)
    end
    if has_j
        push!(i1, 'j')
        push!(i2, 'j')
        push!(s1, sj)
        push!(s2, sj)
    end
    if has_k
        push!(i2, 'k')
        push!(iyb, 'k')
        push!(s2, sk)
    end
    if has_l
        push!(i1, 'l')
        push!(i2, 'l')
        push!(iyb, 'l')
        push!(s1, sl)
        push!(s2, sl)
    end
    return c1, c2, cy, s1, s2, i1, i2, iyb
end

function _analyze_binary_input(ix1::Vector{T}, ix2::Vector{T}, iy::Vector{T}) where T
    ix1_batch = T[]
    ix1_inner = T[]
    ix1_outer = T[]
    for l1 in ix1
        if l1 ∈ ix2
            if l1 ∈ iy  # batch
                l1 ∉ ix1_batch && push!(ix1_batch, l1)
            else        # inner
                l1 ∉ ix1_inner && push!(ix1_inner, l1)
            end
        elseif l1 ∈ iy  # outer
            l1 ∉ ix1_outer && push!(ix1_outer, l1)
        else
            # dangling
        end
    end
    ix2_outer = T[]     # outer dimension of x2
    for l2 in ix2
        if l2 ∉ ix1 && l2 ∈ iy && l2 ∉ ix2_outer
            push!(ix2_outer, l2)
        end
    end
    ix1_inner, ix1_outer, ix2_outer, ix1_batch
end
