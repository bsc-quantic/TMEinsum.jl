module CUDAExt

import OMEinsum: asarray, get_output_array, einsum, loop_einsum!, _batched_gemm!, asscalar, @addmul!
using OMEinsum: EinArray, Diag, Repeat, Duplicate, DefaultRule, EinCode, DynamicEinCode, StaticEinCode, NestedEinsum, SimpleBinaryRule, match_rule, loop_einsum, getiy, getixs, _unique, einarray, align_eltypes, siblings, isleaf, tensorindex, _safe_set, rootcode
import OMEinsum
using LinearAlgebra
import LinearAlgebra: BlasFloat
using CUDA

const CuBlasFloat = Union{BlasFloat, Float16, ComplexF16}
const CUDAArrayTypes{T,N} = Union{LinearAlgebra.Transpose{T,<:CuArray{T,N}}, DenseCuArray{T,N}, LinearAlgebra.Adjoint{T,<:CuArray{T,N}}}
_unwrap(x::LinearAlgebra.Adjoint{T,<:CuArray{T}}) where T = CuArray(x)
_unwrap(x::LinearAlgebra.Transpose{T,<:CuArray{T}}) where T = CuArray(x)
_unwrap(x::CuArray) = x

asarray(x, arr::CuArray) = CuArray(fill(x, ()))
asarray(x::AbstractArray, y::CuArray) = x
asscalar(x::DenseCuArray) = Array(x)[]

Base.Array(x::Base.ReshapedArray{T,0,<:CuArray}) where T = Array(x.parent)

function get_output_array(xs::NTuple{N, DenseCuArray{<:Any,M} where M}, size; fillzero=true) where N
    CUDA.zeros(promote_type(map(eltype,xs)...), size...)
end
function get_output_array(xs::NTuple{N, DenseCuArray{T,M} where M}, size; fillzero=true) where {T,N}
    CUDA.zeros(T, size...)
end

CUDA.cudaconvert(A::EinArray{T}) where T = EinArray{T}(cudaconvert.(A.xs), A.x_indexers, A.y_indexer, A.size, A.ICIS, A.OCIS)
CUDA.cu(A::EinArray{T}) where T = EinArray{T}(cu.(A.xs), A.x_indexers, A.y_indexer, A.size, A.ICIS, A.OCIS)

for TP in [:Diag, :Repeat, :Duplicate, :DefaultRule]
    @eval function einsum(::$TP, ixs, iy, xs::Tuple{<:DenseCuArray}, size_dict::Dict{LT}) where LT
        @debug "cueinsum fallback to loop_einsum" rule ixs => iy size.(xs)
        loop_einsum(EinCode(ixs, iy), xs, size_dict)
    end
end

function einsum(::SimpleBinaryRule{('j',), ('j',), ()}, xs::NTuple{2, DenseCuArray})
    dropdims(reshape(xs[1],1,:) * xs[2]; dims=1)
end

function loop_einsum!(ixs0, iy0,
                xs::NTuple{N, DenseCuArray{<:Any,M} where M},
                y::DenseCuArray{T,L}, size_dict::Dict{LT}, sx, sy) where {N,L,T, LT}
    iy = (iy0...,)
    ixs = (Tuple.(ixs0)...,)
    iy_ = _unique(LT,iy)
    NO = length(iy_)
    if iszero(sy)
        fill!(y, zero(T))
    else
        lmul!(sy, y)
    end
    A = einarray(Val(ixs), Val(iy), xs, size_dict)
    if NO == length(iy)
        raw_ = similar(y, (fill(1, ndims(A)-NO)...,size(y)...,))
        Base.mapreducedim!(x->x, +, raw_, A)
        if ndims(A)-NO > 0  # fix 1.7 compatibility
            raw = dropdims(raw, dims=(1:ndims(A)-NO...,))
        else
            raw = raw_
        end
        return @addmul! sy * y + sx * raw
    else
        y_ = CUDA.zeros(T, size(A)[end-NO+1:end]...)
        y_ = reshape(y_, fill(1, ndims(A)-NO)...,size(y_)...)
        raw = Base.mapreducedim!(x->x, +, y_, A)
        if ndims(A)-NO > 0  # fix 1.7 compatibility
            raw = dropdims(raw, dims=(1:ndims(A)-NO...,))
        end
        return expanddims!(Val{((iy_...,),)}(), Val{iy}(), raw, y, sx)
    end
end

@generated function expandind(::Val{ixs}, ::Val{iy}, ind) where {ixs, iy}
    ix = ixs[1]
    ids = map(ii->:(ind[$(findfirst(==(ii), ix))]), iy)
    Expr(:tuple, ids...)
end

function expanddims!(::Val{ixs}, ::Val{iy}, x, y, sx) where {ixs,iy}
    nthreads = 256
    nblocks = cld(prod(size(x)), nthreads)
    CIS = CartesianIndices(x)
    @inline function kernel(y, x)
        i = (blockIdx().x-1) * blockDim().x + threadIdx().x
        i > length(x) && return nothing
        @inbounds yi = expandind(Val{ixs}(), Val{iy}(), CIS[i].I)
        @inbounds y[CartesianIndex(yi)] = sx * x[i]
        nothing
    end
    @cuda(blocks=nblocks, threads=nthreads, kernel(y, x))
    return y
end

function _batched_gemm!(C1::Char, C2::Char, alpha, A::DenseCuArray{T1,3}, B::DenseCuArray{T2,3}, beta, C) where {T1<:CuBlasFloat, T2<:CuBlasFloat}
    CUDA.CUBLAS.gemm_strided_batched!(C1, C2, alpha, align_eltypes(A,B)..., beta, C)
end

Base.ndims(::Base.Broadcast.Broadcasted{CUDA.CuArrayStyle{0}}) = 0

function einsum(neinsum::NestedEinsum, @nospecialize(xs::NTuple{N,CUDAArrayTypes} where N), size_dict::Dict; active_free=false)
    # do not use map because the static overhead is too large
    # do not use `setindex!` because we need to make the AD work
    mxs = Vector{AbstractArray}(undef, length(siblings(neinsum)))
    for (i, arg) in enumerate(siblings(neinsum))
        mxs = _safe_set(mxs, i, isleaf(arg) ? xs[tensorindex(arg)] : einsum(arg, xs, size_dict; active_free=active_free))
    end
    res = einsum(rootcode(neinsum), (mxs...,), size_dict)
    active_free && for mx in mxs  # free CuArray aggressively.
        CUDA.unsafe_free!(mx)
    end
    return res
end

@info("OMEinsum loaded the CUDA module successfully")

end