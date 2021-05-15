var documenterSearchIndex = {"docs":
[{"location":"parsing/#Input-(flat)","page":"Parsing","title":"Input (flat)","text":"","category":"section"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"An einsum specification should be given via the ein_str string-literal or with the @ein-macro as e.g.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"julia> c = ein\"ij,jk -> ik\"(a,b)\njulia> @ein c[i,k] := a[i,j] * b[j,k]","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"where both specifications encode the same operation - a matrix multiplication. The ein_str-literal is parsed directly into an EinCode struct that holds the indices of the input ixs = (('i','j'),('j','k')) and output iy = ('i','k') as type parameters, making them accessible at compile time.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"The string-literal form gets turned into","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"julia> c = EinCode((('i','j'),('j','k')),('i','k'))(a,b)","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"Calling an EinCode-object gets lowered to","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"julia> c = einsum(EinCode((('i','j'),('j','k')),('i','k')), (a,b), size_dict = nothing)","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"where nothing is the default argument for the (as of yet not used during specification) size_dict, which could allow to provide dimensions for index-labels that only appear in the output.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"In the next step, a singleton-subtype of the abstract type EinRule is chosen which is later used for dispatch. Subtypes of EinRule specify the kind of operation and are created in such a way that they allow useful dispatch. They are defined in EinRule.jl.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"The possible types are:","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"Identity - operation is the identity on one tensor, e.g. ein\"ijk -> ijk\"\nPermutedims - operation is a permutation of the indices of one tensor, e.g. ein\"ijk -> jki\"\nTr - operation is a trace of one matrix, e.g. ein\"ii ->\"\nSum - operation is a reduction over one or more indices of one tensor, e.g. ein\"ijkl -> il\"\nSimpleBinaryRule - operation is a pairwise contraction that can not be reduce by unary operations, e.g. ein\"ijl,jkl-> ikl\"\nDefaultRule - default if none of the above match, e.g. ein\"ij,ik,il -> jkl\"","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"Since ixs and iy are saved as type-parameters, the operation-matching can happen at compile time. The operation is chosen using match_rule(ixs,iy) by testing all subtypes of EinRule in the sequence above (top to bottom) and picking the first match.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"This enables us to chose fast BLAS functions for a  matrix multiplication which is also a legal tensor-contraction.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"We proceed by calling einsum(<:EinRule, <:EinCode, xs, size_dict) which dispatches on the EinRule and the type of xs - the latter enables us to dispatch to e.g. cuda-specific routines for certain operations (as done in the cueinsum.jl file).","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"In the case of the matrix-multiplication above, einsum calls * which can dispatch to efficient routines for most Array-types including CuArray.","category":"page"},{"location":"parsing/#Input-(Nested)","page":"Parsing","title":"Input (Nested)","text":"","category":"section"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"Whether with the ein_str string-literal or the @ein macro, nested expressions are mapped to a nested struct. Consider the example","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"julia> c = ein\"(ij,jk),kl -> il\"(a,b,c)\njulia> @ein c[i,l] := (a[i,j] * b[j,k]) * c[k,l]","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"which is a simply a product of three matrices evaluated as two matrix products in sequence.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"This is equivalent to","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"julia> c = ein\"ik,kl -> il\"(ein\"ij,jk -> ik\"(a,b),c)\njulia> @ein ab[i,k] := a[i,j] * b[j,k]\njulia> @ein c[i,l] := ab[i,k] * c[k,l]","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"and is expressed as a nested structure NestedEinsum which contains the EinCodes for the intermediate calculations as well as some logic to assign the correct input and output tensors to the correct EinCode.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"NestedEinsum has the following definition:","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"struct NestedEinsum\n    args\n    eins\nend","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"args holds the arguments to that EinCode which can either be a integer to label a tensor or a NestedEinsum itself. The labeling works such that the ith input is represented by the number i.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"Upon application to tensors, a NestedEinsum evaluates its arguments. If the argument is an integer i, the ith provided tensor is chosen, otherwise the NestedEinsum is evaluated.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"To make it more concrete, consider the NestedEinsum for the expression above, where for easier reading the type signatures were removed and the EinCode-structs were replaced by ein-string literals.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"julia> ein\"(ij,jk),kl -> il\"\n NestedEinsum{...}((NestedEinsum{...}((1, 2), ein\"ij,jk -> ik\"), 3), ein\"ik,kl -> il\")","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"Evaluating this expression with three arguments leads to the inner NestedEinsum to be evaluated first with the first and second argument and the specifiation ein\"ij,jk -> ik\". Then the result of that is given as the first argument to ein\"ik,kl -> il\" with the third argument as the second input.","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"To improve understanding, you might replace the integers with getindex operations in your head","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"ein\"(ij,jk),kl -> il\"(xs...)\n⇒ NestedEinsum{...}((NestedEinsum{...}((xs[1], xs[2]), ein\"ij,jk -> ik\"), xs[3]), ein\"ik,kl -> il\")","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"and finally turn it into","category":"page"},{"location":"parsing/","page":"Parsing","title":"Parsing","text":"ein\"(ij,jk),kl -> il\"(xs...)\n⇒ ein\"ik,kl -> il\"(ein\"ij,jk -> ik\"(xs[1], xs[2]), xs[3])","category":"page"},{"location":"extending/#Extending-OMEinsum","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"","category":"section"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"Adding a new subtype of EinRule is bothersome - the list of rules that's considered needs to be fix and thus one has to change the code before using OMEinsum. A limitation due to liberal use of generated functions. If a useful rule is found, we might add it to the package itself though so feel free to reach out.","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"Extending einsum for certain array-types on the other hands is easy, since we use the usual dispatch mechanism. Consider e.g. adding a special operator for index-reductions of a Diagonal-operator.","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"First, we need to add a method for the asarray-function that ensures that we return 0-dimensional arrays for operations.","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"julia> OMEinsum.asarray(a::Number, ::Diagonal) = fill(a,())","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"Now reducing over indices already works but it uses the sum function which does not specialize on Diagonal:","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"julia> ein\"ij -> \"(Diagonal([1,2,3]))\n0-dimensional Array{Int64,0}:\n6","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"we can do better by overloading einsum(::Sum, ::EinCode, ::Tuple{<:Diagonal}, <:Any):","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"julia> function OMEinsum.einsum(::OMEinsum.Sum, ::EinCode{ixs,iy}, xs::Tuple{<:Diagonal}, size_dict) where {ixs, iy}\n    length(iy) == 1 && return diag(xs[1])\n    return sum(diag(xs[1]))\nend","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"where we use that the indices iy and ixs have already been checked in match_rule. We now get our more efficient implementation when we call any of the below:","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"julia> ein\"ij -> i\"(Diagonal([1,2,3]))\n3-element Array{Int64,1}:\n 1\n 2\n 3\n\njulia> ein\"ij -> j\"(Diagonal([1,2,3]))\n3-element Array{Int64,1}:\n 1\n 2\n 3\n\njulia> ein\"ij -> \"(Diagonal([1,2,3]))\n6","category":"page"},{"location":"extending/","page":"Extending OMEinsum","title":"Extending OMEinsum","text":"(To make sure the custom implementation is called, you can add a print-statement to the method for Diagonal)","category":"page"},{"location":"#OMEinsum.jl","page":"Home","title":"OMEinsum.jl","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"This package exports one function, einsum, with three interfaces. einsum implements functionality similar to the einsum function in numpy, although some details are different.","category":"page"},{"location":"","page":"Home","title":"Home","text":"einsum operations are specified by a tuple of tensors xs = (x1, x2, x3...) , a tuple of index-labels for the tensors in xs, ixs = (ix1, ix2, ix3...), and output index-labels iy specified as einsum(EinCode(ixs,iy), xs). Alternatively, operations can be specified using the @ein-macro or the @ein_str- string literal (see examples or help).","category":"page"},{"location":"","page":"Home","title":"Home","text":"Let l be the set of all unique labels in the ixs without the ones in iy. einsum then calculates an output tensor y with indices labelled iy according to the following specification:","category":"page"},{"location":"","page":"Home","title":"Home","text":"forall iy  yiy = sum_l x_1ix_1 * x_2ix_2 * x_3ix_3 ldots","category":"page"},{"location":"","page":"Home","title":"Home","text":"where the sum over l implies the sum over all possible values of the labels in l.","category":"page"},{"location":"","page":"Home","title":"Home","text":"As an example, consider the matrix multiplication of two random 2×2 tensors, where we have:","category":"page"},{"location":"","page":"Home","title":"Home","text":"xs = (rand(2,2), rand(2,2))\nixs = (('i','j'),('j','k'))\niy = ('i','k')","category":"page"},{"location":"","page":"Home","title":"Home","text":"Now l = ('j',) since all unique indices are ('i','j','k') but both 'i' and 'k' are in iy. The output y is then defined by","category":"page"},{"location":"","page":"Home","title":"Home","text":"forall ik  yik = sum_j x_1ij * x_2jk","category":"page"},{"location":"","page":"Home","title":"Home","text":"which is just the regular definition of matrix multiplication. Alternatively it could've been specified with a custom string-literal as ein\"ij,jk -> ik\"(rand(2,2),rand(2,2)), see Input (flat).","category":"page"},{"location":"","page":"Home","title":"Home","text":"The structure of an einsum evaluation with the string-literal is depicted in the flowchart below: (Image: )","category":"page"},{"location":"implementation/#Implementations","page":"Implementations","title":"Implementations","text":"","category":"section"},{"location":"implementation/#Identity","page":"Implementations","title":"Identity","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"To test whether a specification ixs,iy is the identity, it is checked whether ixs is made up of one tuple of index-labels that is equal to iy and that all index-labels in iy are unique - the latter to distuingish identity from e.g. projection to the diagonal like ein\"ii -> ii\".","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"The identity operation simply returns the first (and only) tensor argument to einsum.","category":"page"},{"location":"implementation/#Permutations","page":"Implementations","title":"Permutations","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"A specification ixs,iy is an index-permutation if ixs is a tuple containing one tuple of index-labels that are all unique and are a permutation of the labels in iy.","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"Index-permutation is implemented with permutedims and a permutation that's calculated at runtime.","category":"page"},{"location":"implementation/#Tr","page":"Implementations","title":"Tr","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"A specification ixs, iy is a trace if iy is empty and ixs contains one 2-tuple containing the same index-label twice.","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"A trace dispatches to the LinearAlgebra.tr although the result is wrapped in a 0-dimensional array for type stability since all einsum return AbstractArrays.","category":"page"},{"location":"implementation/#Sum","page":"Implementations","title":"Sum","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"A specification ixs,iy is a sum or a reduction over indices if all indices in iy are unique and contained in the only tuple in ixs that additionally contains unique labels (that are reduced over).","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"Index-reductions are implemented using Base.sum and Base.dropdims - the latter to remove the singleton-dimensions left over after summing over a dimension.","category":"page"},{"location":"implementation/#Repeat","page":"Implementations","title":"Repeat","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"The inverse rule of Sum, e.g. ij->lijk.","category":"page"},{"location":"implementation/#Diag","page":"Implementations","title":"Diag","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"A unary operation that remove multi-edges from a tensor, e.g. ijkj->ikj.","category":"page"},{"location":"implementation/#Duplicate","page":"Implementations","title":"Duplicate","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"The inverse rule of Diag, e.g. ikj->ijkj.","category":"page"},{"location":"implementation/#SimpleBinaryRule","page":"Implementations","title":"SimpleBinaryRule","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"The contraction between two tensors with the following restriction","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"a tensor can not be simplified by unary rules, e.g. iij,jk,ik is not valid, the first index can be simplified to ij using the unary rule iij->ij.\nno multi-edge","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"A complete list of rules are","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"ein\",->\"\nein\",k->k\"\nein\"i,->i\"\nein\"j,j->\"\nein\"i,k->ik\" and ein\"i,k->ki\",\nein\"j,jk->k\" and ein\"j,kj->k\"\nein\"ji,j->i\" and ein\"ij,j->i\"\nein\"ji,jk->ik\" and its index permutations (within a tensor)\nein\"l,l->l\"\nein\"l,kl->kl\"\nein\"il,->il\"\nein\"jl,jl->\"\nein\"il,kl->ikl\" and ein\"il,kl->kil\",\nein\"jl,jkl->kl\" and ein\"jl,kjl->kl\"\nein\"jil,jl->il\" and ein\"ijl,jl->il\"\nein\"jil,jkl->ikl\" and its index permutations (within a tensor, except the batch dimension)","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"Here, the batch dimension always appears as the last dimension.","category":"page"},{"location":"implementation/#Fallback","page":"Implementations","title":"Fallback","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"The fallback is called for any specification that does not satisfy the criteria outlined above.","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"The dispatch calls loop_einsum which is defined in loop_einsum.jl.","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"loop_einsum is based on the EinArray-struct. An EinArray is a subtype of AbstractArray that represents an intermediate step in a general einsum-expression before reductions remove indices. Consider a specification ixs,iy - the EinArray for that specification is the array with an index for each (distinct) label in ixs and iy. As an example, in ein\"ij,ik,il -> jkl\"(a,b,c), the distinct labels are (i,j,k,l) and the corresponding EinArray einarr would be a rank-4 tensor with an index each for each distinct label.","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"If an entry of einarr is requested, e.g. einarr[i₁,j₁,k₁,l₁], it's values is lazily constructed as einarr[i₁,j₁,k₁,l₁] = a[i₁,j₁]*a[i₁,k₁]*a[i₁,l₁] upon access - the lazy evaluation avoids constructing the whole array.","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"To get to the final result, we reduce over the dimensions that are missing in the output. By first allocating an array of the correct size, we can fill it up with the entries of the EinArray which are calculated on the fly, avoiding the allocation of the intermediate result.","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"Thus effectively we split an operation like ein\"ij,ik,il -> jkl\"(a,b,c) into two piece: einarr = ein\"ij,ik,il -> ijkl\"(a,b,c) and ein\"ijkl -> jkl\"(einarr) but treat the first operation as a lazy one - this way we can use mapreduce(identity, +) over the dimensions we want to remove which is implemented efficiently for both regular Arrays and CuArrays.","category":"page"},{"location":"implementation/#Debugging","page":"Implementations","title":"Debugging","text":"","category":"section"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"Calling allow_loops(false) will cause an error to be pinted when if the  fallback loop_einsum is used. This is an @error which does not interrupt execution. ","category":"page"},{"location":"implementation/","page":"Implementations","title":"Implementations","text":"Alternatively, a log of all methods used can be saved using @debug logging macro.  This is switched off by default, but can be printed by setting ENV[\"JULIA_DEBUG\"] = \"all\".","category":"page"},{"location":"docstrings/","page":"DocStrings","title":"DocStrings","text":"Modules = [OMEinsum]","category":"page"},{"location":"docstrings/#OMEinsum.EinArray","page":"DocStrings","title":"OMEinsum.EinArray","text":"EinArray{T, N, TT, LX, LY, ICT, OCT} <: AbstractArray{T, N}\n\nA struct to hold the intermediate result of an einsum where all index-labels of both input and output are expanded to a rank-N-array whose values are lazily calculated. Indices are arranged as inner indices (or reduced dimensions) first and then outer indices.\n\nType parameters are\n\n* `T`: element type,\n* `N`: array dimension,\n* `TT`: type of \"tuple of input arrays\",\n* `LX`: type of \"tuple of input indexers\",\n* `LX`: type of output indexer,\n* `ICT`: typeof inner CartesianIndices,\n* `OCT`: typeof outer CartesianIndices,\n\n\n\n\n\n","category":"type"},{"location":"docstrings/#OMEinsum.EinCode","page":"DocStrings","title":"OMEinsum.EinCode","text":"EinCode{ixs, iy}\n\nWrapper to eincode-specification that creates a callable object to evaluate the eincode ixs -> iy where ixs are the index-labels of the input-tensors and iy are the index-labels of the output\n\nexample\n\njulia> a, b = rand(2,2), rand(2,2);\n\njulia> EinCode((('i','j'),('j','k')),('i','k'))(a, b) ≈ a * b\ntrue\n\n\n\n\n\n","category":"type"},{"location":"docstrings/#OMEinsum.EinIndexer","page":"DocStrings","title":"OMEinsum.EinIndexer","text":"EinIndexer{locs,N}\n\nA structure for indexing EinArrays. locs is the index positions (among all indices). In the constructor, size is the size of target tensor,\n\n\n\n\n\n","category":"type"},{"location":"docstrings/#OMEinsum.EinIndexer-Union{Tuple{Tuple{Vararg{Int64, N}}}, Tuple{locs}, Tuple{N}} where {N, locs}","page":"DocStrings","title":"OMEinsum.EinIndexer","text":"EinIndexer{locs}(size::Tuple)\n\nConstructor for EinIndexer for an object of size size where locs are the locations of relevant indices in a larger tuple.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.IndexGroup","page":"DocStrings","title":"OMEinsum.IndexGroup","text":"IndexGroup\n\nLeaf in a contractiontree, contains the indices and the number of the tensor it describes, e.g. in \"ij,jk -> ik\", indices \"ik\" belong to tensor 1, so would be described by IndexGroup(['i','k'], 1).\n\n\n\n\n\n","category":"type"},{"location":"docstrings/#OMEinsum.NestedEinsumConstructor","page":"DocStrings","title":"OMEinsum.NestedEinsumConstructor","text":"NestedEinsumConstructor\n\ndescribes a (potentially) nested einsum. Important fields:\n\nargs, vector of all inputs, either IndexGroup objects corresponding to tensors or NestedEinsumConstructor\niy, indices of output\n\n\n\n\n\n","category":"type"},{"location":"docstrings/#Base.getindex-Union{Tuple{T}, Tuple{EinArray{T, N, TT, LX, LY, ICT, OCT} where {N, TT, LX, LY, ICT, OCT}, Any}} where T","page":"DocStrings","title":"Base.getindex","text":"getindex(A::EinArray, inds...)\n\nreturn the lazily calculated entry of A at index inds.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.allow_loops-Tuple{Bool}","page":"DocStrings","title":"OMEinsum.allow_loops","text":"allow_loops(flag::Bool)\n\nSetting this to false will cause OMEinsum to log an error if it falls back to loop_einsum evaluation, instead of calling specialised kernels. The default is true.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.allunique-Tuple{Any}","page":"DocStrings","title":"OMEinsum.allunique","text":"allunique(ix::Tuple)\n\nreturn true if all elements of ix appear only once in ix.\n\nexample\n\njulia> using OMEinsum: allunique\n\njulia> allunique((1,2,3,4))\ntrue\n\njulia> allunique((1,2,3,1))\nfalse\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.analyze_binary-Union{Tuple{T}, Tuple{Vector{T}, Vector{T}, Vector{T}, Dict{T, Int64}}} where T","page":"DocStrings","title":"OMEinsum.analyze_binary","text":"Get the expected labels.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.asarray-Tuple{Number}","page":"DocStrings","title":"OMEinsum.asarray","text":"asarray(x::Number[, parent::AbstractArray]) -> AbstactArray\n\nReturn a 0-dimensional array with item x, otherwise, do nothing. If a parent is supplied, it will try to match the parent array type.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.einarray-Union{Tuple{TT}, Tuple{NI}, Tuple{iy}, Tuple{ixs}, Tuple{EinCode{ixs, iy}, TT, Any}} where {ixs, iy, NI, TT<:Tuple{Vararg{AbstractArray, NI}}}","page":"DocStrings","title":"OMEinsum.einarray","text":"einarray(::EinCode, xs, size_dict) -> EinArray\n\nConstructor of EinArray from an EinCode, a tuple of tensors xs and a size_dict that assigns each index-label a size. The returned EinArray holds an intermediate result of the einsum specified by the EinCode with indices corresponding to all unique labels in the einsum. Reduction over the (lazily calculated) dimensions that correspond to labels not present in the output lead to the result of the einsum.\n\nexample\n\njulia> using OMEinsum: get_size_dict\n\njulia> a, b = rand(2,2), rand(2,2);\n\njulia> sd = get_size_dict((('i','j'),('j','k')), (a, b));\n\njulia> ea = OMEinsum.einarray(EinCode((('i','j'),('j','k')),('i','k')), (a,b), sd);\n\njulia> dropdims(sum(ea, dims=1), dims=1) ≈ a * b\ntrue\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.einsum-Union{Tuple{LT}, Tuple{iy}, Tuple{ixs}, Tuple{EinCode{ixs, iy}, Any, Dict{LT, V} where V}} where {ixs, iy, LT}","page":"DocStrings","title":"OMEinsum.einsum","text":"einsum(::EinCode{ixs, iy}, xs, size_dict) where {ixs, iy}\n\nreturn the tensor that results from contracting the tensors xs according to their indices ixs, where all indices that do not appear in the output iy are summed over. The result is permuted according to out.\n\nixs - tuple of tuples of index-labels of the input-tensors xs\niy - tuple of index-labels of the output-tensor\nxs - tuple of tensors\nsize_dict - a dictionary that maps index-labels to their sizes\n\nexample\n\njulia> a, b = rand(2,2), rand(2,2);\n\njulia> einsum(EinCode((('i','j'),('j','k')),('i','k')), (a, b)) ≈ a * b\ntrue\n\njulia> einsum(EinCode((('i','j'),('j','k')),('k','i')), (a, b)) ≈ permutedims(a * b, (2,1))\ntrue\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.einsum_grad-NTuple{6, Any}","page":"DocStrings","title":"OMEinsum.einsum_grad","text":"einsum_grad(ixs, xs, iy, size_dict, cdy, i)\n\nreturn the gradient of the result of evaluating the EinCode w.r.t the ith tensor in xs. cdy is the result of applying the EinCode to the xs.\n\nexample\n\njulia> using OMEinsum: einsum_grad, get_size_dict\n\njulia> a, b = rand(2,2), rand(2,2);\n\njulia> c = einsum(EinCode((('i','j'),('j','k')), ('i','k')), (a,b));\n\njulia> sd = get_size_dict((('i','j'),('j','k')), (a,b));\n\njulia> einsum_grad((('i','j'),('j','k')), (a,b), ('i','k'), sd, c, 1) ≈ c * transpose(b)\ntrue\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.filliys!-Tuple{Any}","page":"DocStrings","title":"OMEinsum.filliys!","text":"filliys!(neinsum::NestedEinsumConstructor)\n\ngoes through all NestedEinsumConstructor objects in the tree and saves the correct iy in them.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.get_size_dict","page":"DocStrings","title":"OMEinsum.get_size_dict","text":"get_size_dict(ixs, xs, size_info=nothing)\n\nreturn a dictionary that is used to get the size of an index-label in the einsum-specification with input-indices ixs and tensors xs after consistency within ixs and between ixs and xs has been verified.\n\n\n\n\n\n","category":"function"},{"location":"docstrings/#OMEinsum.indices_and_locs-Tuple{Any, Any}","page":"DocStrings","title":"OMEinsum.indices_and_locs","text":"indices_and_locs(ixs,iy)\n\ngiven the index-labels of input and output of an einsum, return (in the same order):\n\na tuple of the distinct index-labels of the output iy\na tuple of the distinct index-labels in ixs of the input not appearing in the output iy\na tuple of tuples of locations of an index-label in the ixs in a list of all index-labels\na tuple of locations of index-labels in iy in a list of all index-labels\n\nwhere the list of all index-labels is simply the first  and the second output catenated and the second output catenated.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.loop_einsum!-Union{Tuple{iy}, Tuple{ixs}, Tuple{IT}, Tuple{T}, Tuple{L}, Tuple{N}, Tuple{EinCode{ixs, iy}, Tuple{Vararg{AbstractArray{var\"#s4\", M} where {M, var\"#s4\"}, N}}, AbstractArray{T, L}, Any}} where {N, L, T, IT<:Union{AbstractChar, Integer}, ixs, iy}","page":"DocStrings","title":"OMEinsum.loop_einsum!","text":"loop_einsum!(::EinCode, xs, y, size_dict)\n\ninplace-version of loop_einsum, saving the result in a preallocated tensor of correct size y.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.loop_einsum-Union{Tuple{iy}, Tuple{ixs}, Tuple{N}, Tuple{EinCode{ixs, iy}, Tuple{Vararg{AbstractArray{var\"#s4\", M} where {M, var\"#s4\"}, N}}, Any}} where {N, ixs, iy}","page":"DocStrings","title":"OMEinsum.loop_einsum","text":"loop_einsum(::EinCode, xs, size_dict)\n\nevaluates the eincode specified by EinCode and the tensors xs by looping over all possible indices and calculating the contributions ot the result. Scales exponentially in the number of distinct index-labels.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.map_prod-Union{Tuple{N}, Tuple{Tuple, Any, Tuple{Vararg{Any, N}}}} where N","page":"DocStrings","title":"OMEinsum.map_prod","text":"map_prod(xs, ind, indexers)\n\ncalculate the value of an EinArray with EinIndexers indexers at location ind.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.match_rule-Tuple{Tuple{Vararg{Tuple{Vararg{T, N}} where {N, T}, Nx}} where Nx, Tuple}","page":"DocStrings","title":"OMEinsum.match_rule","text":"match_rule(ixs, iy)\nmatch_rule(code::EinCode{ixs, iy})\nmatch_rule(code::NestedEinCode)\n\nReturns the rule that matches, otherwise use DefaultRule - the slow loop_einsum backend.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.nopermute-Tuple{Tuple{Vararg{T, N}} where {N, T}, Tuple{Vararg{T, N}} where {N, T}}","page":"DocStrings","title":"OMEinsum.nopermute","text":"nopermute(ix,iy)\n\ncheck that all values in iy that are also in ix have the same relative order,\n\nexample\n\njulia> using OMEinsum: nopermute\n\njulia> nopermute((1,2,3),(1,2))\ntrue\n\njulia> nopermute((1,2,3),(2,1))\nfalse\n\ne.g. nopermute((1,2,3),(1,2)) is true while nopermute((1,2,3),(2,1)) is false\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.parse_parens-Tuple{AbstractString, Any, Any}","page":"DocStrings","title":"OMEinsum.parse_parens","text":"parse_parens(s::AbstractString, i, narg)\n\nparse one level of parens starting at index i where narg counts which tensor the current group of indices, e.g. \"ijk\", belongs to. Recursively calls itself for each new opening paren that's opened.\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.tensorpermute-Tuple{AbstractArray, Any}","page":"DocStrings","title":"OMEinsum.tensorpermute","text":"tensorpermute(A, perm)\n\nAliasing permutedims(A, perm).\n\n\n\n\n\n","category":"method"},{"location":"docstrings/#OMEinsum.@ein-Tuple","page":"DocStrings","title":"OMEinsum.@ein","text":"@ein A[i,k] := B[i,j] * C[j,k]     # A = B * C\n\nMacro interface similar to that of other packages.\n\nYou may use numbers in place of letters for dummy indices, as in @tensor, and need not name the output array. Thus A = @ein [1,2] := B[1,ξ] * C[ξ,2] is equivalent to the above. This can also be written A = ein\"ij,jk -> ik\"(B,C) using the numpy-style string macro.\n\nexample\n\njulia> a, b = rand(2,2), rand(2,2);\n\njulia> @ein c[i,k] := a[i,j] * b[j,k];\n\njulia> c ≈ a * b\ntrue\n\njulia> c ≈ ein\"ij,jk -> ik\"(a,b)\ntrue\n\n\n\n\n\n","category":"macro"},{"location":"docstrings/#OMEinsum.@ein_str-Tuple{AbstractString}","page":"DocStrings","title":"OMEinsum.@ein_str","text":"ein\"ij,jk -> ik\"(A,B)\n\nString macro interface which understands numpy.einsum's notation. Translates strings into EinCode-structs that can be called to evaluate an einsum. To control evaluation order, use parentheses - instead of an EinCode, a NestedEinsum is returned which evaluates the expression according to parens. The valid character ranges for index-labels are a-z and α-ω.\n\nexample\n\njulia> a, b, c = rand(10,10), rand(10,10), rand(10,1);\n\njulia> ein\"ij,jk,kl -> il\"(a,b,c) ≈ ein\"(ij,jk),kl -> il\"(a,b,c) ≈ a * b * c\ntrue\n\n\n\n\n\n","category":"macro"}]
}
