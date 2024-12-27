using OMEinsum
using Test
using LinearAlgebra
using CUDA
import Documenter


@testset "Core" begin
    include("Core.jl")
end

@testset "match rule" begin
    include("matchrule.jl")
end

@testset "unary rules" begin
    include("unaryrules.jl")
end

@testset "binary rules" begin
    include("binaryrules.jl")
end

@testset "utils" begin
    include("utils.jl")
end

@testset "einsum" begin
    include("einsum.jl")
end

@testset "cuda" begin
    if CUDA.functional()
        include("cueinsum.jl")
    end
end

@testset "interfaces" begin
    include("interfaces.jl")
end

@testset "docstring" begin
    Documenter.doctest(OMEinsum; manual=false)
end
