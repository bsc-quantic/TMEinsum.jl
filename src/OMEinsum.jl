module OMEinsum

using TupleTools, Base.Cartesian, LinearAlgebra
using BatchedRoutines
import LinearAlgebra: BlasFloat

export @ein_str, @ein, @ein!, ein, @optein_str
export einsum!, einsum, dynamic_einsum
export EinCode, EinIndexer, EinArray, DynamicEinCode, StaticEinCode, AbstractEinsum
export getiyv, getixsv, uniquelabels, labeltype
export flop
export loop_einsum, loop_einsum!, allow_loops
export asarray, asscalar

include("Core.jl")
include("loop_einsum.jl")
include("utils.jl")

include("unaryrules.jl")
include("binaryrules.jl")
include("matchrule.jl")
include("einsum.jl")

include("interfaces.jl")

end # module
