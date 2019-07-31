function calc_tderivative!(integrator, cache, dtd1, repeat_step)
  @inbounds begin
    @unpack t,dt,uprev,u,f,p = integrator
    @unpack du2,fsalfirst,dT,tf,linsolve_tmp = cache

    # Time derivative
    if !repeat_step # skip calculation if step is repeated
      if DiffEqBase.has_tgrad(f)
        f.tgrad(dT, uprev, p, t)
      else
        tf.uprev = uprev
        tf.p = p
        derivative!(dT, tf, t, du2, integrator, cache.grad_config)
      end
    end

    f(fsalfirst, uprev, p, t)
    # For when destats come here
    # integrator.destats.nf += 1
    @.. linsolve_tmp = fsalfirst + dtd1*dT
  end
end

function calc_tderivative(integrator, cache)
  @unpack t,dt,uprev,u,f,p = integrator

  # Time derivative
  if DiffEqBase.has_tgrad(f)
    dT = f.tgrad(uprev, p, t)
  else
    tf = cache.tf
    tf.u = uprev
    tf.p = p
    dT = derivative(tf, t, integrator)
  end
  dT
end

"""
    calc_J(integrator,cache,is_compos)

Interface for calculating the jacobian.

For constant caches, a new jacobian object is returned whereas for mutable
caches `cache.J` is updated. In both cases, if `integrator.f` has a custom
jacobian update function, then it will be called for the update. Otherwise,
either ForwardDiff or finite difference will be used depending on the
`jac_config` of the cache.
"""
function calc_J(nlsolver, integrator, cache::StochasticDiffEqConstantCache, is_compos)
  @unpack t,dt,uprev,u,f,p = integrator
  if DiffEqBase.has_jac(f)
    J = f.jac(uprev, p, t)
  else
    J = jacobian(nlsolver.uf,uprev,integrator)
  end
  # integrator.destats.njacs += 1
  is_compos && (integrator.eigen_est = opnorm(J, Inf))
  return J
end

"""
    calc_J!(integrator,cache,is_compos)

Interface for calculating the jacobian.

For constant caches, a new jacobian object is returned whereas for mutable
caches `cache.J` is updated. In both cases, if `integrator.f` has a custom
jacobian update function, then it will be called for the update. Otherwise,
either ForwardDiff or finite difference will be used depending on the
`jac_config` of the cache.
"""
function calc_J!(nlsolver, integrator, cache::StochasticDiffEqMutableCache, is_compos)
  @unpack t,dt,uprev,u,f,p = integrator
  J = nlsolver.cache.J
  if DiffEqBase.has_jac(f)
    f.jac(J, uprev, p, t)
  else
    @unpack du1,uf,jac_config = nlsolver
    uf.t = t
    uf.p = p
    jacobian!(J, uf, uprev, du1, integrator, jac_config)
  end
  # integrator.destats.njacs += 1
  is_compos && (integrator.eigen_est = opnorm(J, Inf))
end

"""
    WOperator(mass_matrix,gamma,J[;transform=false])

A linear operator that represents the W matrix of an SDEProblem, defined as

```math
W = MM - \\gamma J
```

or, if `transform=true`:

```math
W = \\frac{1}{\\gamma}MM - J
```

where `MM` is the mass matrix (a regular `AbstractMatrix` or a `UniformScaling`),
`γ` is a real number proportional to the time step, and `J` is the Jacobian
operator (must be a `AbstractDiffEqLinearOperator`). A `WOperator` can also be
constructed using a `*DEFunction` directly as

    WOperator(f,gamma[;transform=false])

`f` needs to have a jacobian and `jac_prototype`, but the prototype does not need
to be a diffeq operator --- it will automatically be converted to one.

`WOperator` supports lazy `*` and `mul!` operations, the latter utilizing an
internal cache (can be specified in the constructor; default to regular `Vector`).
It supports all of `AbstractDiffEqLinearOperator`'s interface.
"""
mutable struct WOperator{T,
  MType <: Union{UniformScaling,AbstractMatrix},
  GType <: Real,
  JType <: DiffEqBase.AbstractDiffEqLinearOperator{T}
  } <: DiffEqBase.AbstractDiffEqLinearOperator{T}
  mass_matrix::MType
  gamma::GType
  J::JType
  transform::Bool       # true => W = mm/gamma - J; false => W = mm - gamma*J
  inplace::Bool
  _func_cache           # cache used in `mul!`
  _concrete_form         # non-lazy form (matrix/number) of the operator
  WOperator(mass_matrix, gamma, J, inplace; transform=false) = new{eltype(J),typeof(mass_matrix),
    typeof(gamma),typeof(J)}(mass_matrix,gamma,J,transform,inplace,nothing,nothing)
end
function WOperator(f::DiffEqBase.AbstractSDEFunction, gamma, inplace; transform=false)
  @assert DiffEqBase.has_jac(f) "f needs to have an associated jacobian"
  if isa(f, SplitSDEFunction)
    error("WOperator does not support $(typeof(f)) yet")
  end
  # Convert mass matrix, if needed
  mass_matrix = f.mass_matrix
  if !isa(mass_matrix, Union{AbstractMatrix,UniformScaling})
    mass_matrix = convert(AbstractMatrix, mass_matrix)
  end
  # Convert jacobian, if needed
  J = deepcopy(f.jac_prototype)
  if !isa(J, DiffEqBase.AbstractDiffEqLinearOperator)
    J = DiffEqArrayOperator(J; update_func=f.jac)
  end
  return WOperator(mass_matrix, gamma, J, inplace; transform=transform)
end

set_gamma!(W::WOperator, gamma) = (W.gamma = gamma; W)
DiffEqBase.update_coefficients!(W::WOperator,u,p,t) = (update_coefficients!(W.J,u,p,t); W)
function Base.convert(::Type{AbstractMatrix}, W::WOperator)
  if W._concrete_form === nothing || !W.inplace
    # Allocating
    if W.transform
      W._concrete_form = -W.mass_matrix / W.gamma + convert(AbstractMatrix,W.J)
    else
      W._concrete_form = -W.mass_matrix + W.gamma * convert(AbstractMatrix,W.J)
    end
  else
    # Non-allocating
    _W = W._concrete_form
    J = convert(AbstractMatrix,W.J)
    if W.transform
      if _W isa Diagonal # axpby doesn't specialize on Diagonal matrix
        @inbounds for i in axes(W._concrete_form, 1)
          _W[i, i] = J[i, i] - inv(W.gamma) * W.mass_matrix[i, i]
        end
      else
        copyto!(_W, W.mass_matrix)
        axpby!(one(W.gamma), J, -inv(W.gamma), _W)
      end
    else
      if _W isa Diagonal # axpby doesn't specialize on Diagonal matrix
        @inbounds for i in axes(W._concrete_form, 1)
          _W[i, i] = W.gamma*J[i, i] - W.mass_matrix[i, i]
        end
      else
        copyto!(_W, W.mass_matrix)
        axpby!(W.gamma, J, -one(W.gamma), W._concrete_form)
      end
    end
  end
  W._concrete_form
end
function Base.convert(::Type{Number}, W::WOperator)
  if W.transform
    W._concrete_form = -W.mass_matrix / W.gamma + convert(Number,W.J)
  else
    W._concrete_form = -W.mass_matrix + W.gamma * convert(Number,W.J)
  end
  W._concrete_form
end
Base.size(W::WOperator, args...) = size(W.J, args...)
function Base.getindex(W::WOperator, i::Int)
  if W.transform
    -W.mass_matrix[i] / W.gamma + W.J[i]
  else
    -W.mass_matrix[i] + W.gamma * W.J[i]
  end
end
function Base.getindex(W::WOperator, I::Vararg{Int,N}) where {N}
  if W.transform
    -W.mass_matrix[I...] / W.gamma + W.J[I...]
  else
    -W.mass_matrix[I...] + W.gamma * W.J[I...]
  end
end
function Base.:*(W::WOperator, x::Union{AbstractVecOrMat,Number})
  if W.transform
    (W.mass_matrix*x) / -W.gamma + W.J*x
  else
    -W.mass_matrix*x + W.gamma * (W.J*x)
  end
end
function Base.:\(W::WOperator, x::Union{AbstractVecOrMat,Number})
  if size(W) == () # scalar operator
    convert(Number,W) \ x
  else
    convert(AbstractMatrix,W) \ x
  end
end

function LinearAlgebra.mul!(Y::AbstractVecOrMat, W::WOperator, B::AbstractVecOrMat)
  if W._func_cache === nothing
    # Allocate cache only if needed
    W._func_cache = Vector{eltype(W)}(undef, size(Y, 1))
  end
  if W.transform
    # Compute mass_matrix * B
    if isa(W.mass_matrix, UniformScaling)
      a = -W.mass_matrix.λ / W.gamma
      @.. Y = a * B
    else
      mul!(Y, W.mass_matrix, B)
      lmul!(-1/W.gamma, Y)
    end
    # Compute J * B and add
    mul!(W._func_cache, W.J, B)
    Y .+= W._func_cache
  else
    # Compute mass_matrix * B
    if isa(W.mass_matrix, UniformScaling)
      @.. Y = W.mass_matrix.λ * B
    else
      mul!(Y, W.mass_matrix, B)
    end
    # Compute J * B
    mul!(W._func_cache, W.J, B)
    # Add result
    axpby!(W.gamma, W._func_cache, -one(W.gamma), Y)
  end
end

function do_newJ(nlsolver, integrator, alg::T, cache, repeat_step)::Bool where T
  repeat_step && return false
  !integrator.opts.adaptive && return true
  !alg_can_repeat_jac(alg) && return true
  isnewton = T <: Union{StochasticDiffEqNewtonAdaptiveAlgorithm, StochasticDiffEqNewtonAlgorithm}
  isnewton && ( nlstatus = DiffEqBase.get_status(nlsolver) )
  nlsolvefail(nlstatus) && return true
  # reuse J when there is fast convergence
  fastconvergence = nlstatus === FastConvergence
  return !fastconvergence
end

function do_newW(integrator, nlsolver::T, new_jac, W_dt)::Bool where T # any changes here need to be reflected in FIRK
  integrator.iter <= 1 && return true
  new_jac && return true
  # reuse W when the change in stepsize is small enough
  dt = integrator.dt
  new_W_dt_cutoff = T <: NLSolver ? nlsolver.cache.new_W_dt_cutoff : #= FIRK =# nlsolver.new_W_dt_cutoff
  smallstepchange = (dt/W_dt-one(dt)) <= new_W_dt_cutoff
  return !smallstepchange
end

@noinline _throwWJerror(W, J) = throw(DimensionMismatch("W: $(axes(W)), J: $(axes(J))"))
@noinline _throwWMerror(W, mass_matrix) = throw(DimensionMismatch("W: $(axes(W)), mass matrix: $(axes(mass_matrix))"))

@inline function jacobian2W!(W::AbstractMatrix, mass_matrix::MT, dtgamma::Number, J::AbstractMatrix, W_transform::Bool)::Nothing where MT
  # check size and dimension
  iijj = axes(W)
  @boundscheck (iijj === axes(J) && length(iijj) === 2) || _throwWJerror(W, J)
  mass_matrix isa UniformScaling || @boundscheck axes(mass_matrix) === axes(W) || _throwWMerror(W, mass_matrix)
  @inbounds if W_transform
    invdtgamma = inv(dtgamma)
    if MT <: UniformScaling
      copyto!(W, J)
      @simd for i in diagind(W)
          W[i] = muladd(-mass_matrix.λ, invdtgamma, J[i])
      end
    else
      for j in iijj[2]
        @simd for i in iijj[1]
          W[i, j] = muladd(-mass_matrix[i, j], invdtgamma, J[i, j])
        end
      end
    end
  else
    for j in iijj[2]
      @simd for i in iijj[1]
        W[i, j] = muladd(dtgamma, J[i, j], -mass_matrix[i, j])
      end
    end
  end
  return nothing
end

function calc_W!(nlsolver, integrator, cache::StochasticDiffEqMutableCache, dtgamma, repeat_step, W_transform=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack J,W = nlsolver.cache
  alg = unwrap_alg(integrator, true)
  mass_matrix = integrator.f.mass_matrix
  is_compos = integrator.alg isa StochasticCompositeAlgorithm
  isnewton = alg isa Union{StochasticDiffEqNewtonAdaptiveAlgorithm, StochasticDiffEqNewtonAlgorithm}

  # fast pass
  # we only want to factorize the linear operator once
  new_jac = true
  new_W = true
  if (f isa SDEFunction && islinear(f.f)) || (f isa SplitSDEFunction && islinear(f.f1.f))
    new_jac = false
    @goto J2W # Jump to W calculation directly, because we already have J
  end

  # check if we need to update J or W
  W_dt = isnewton ? nlsolver.cache.W_dt : dt # TODO: RosW
  new_jac = isnewton ? do_newJ(nlsolver, integrator, alg, cache, repeat_step) : true
  new_W = isnewton ? do_newW(integrator, nlsolver, new_jac, W_dt) : true

  # calculate W
  if DiffEqBase.has_jac(f) && f.jac_prototype !== nothing
    isnewton || DiffEqBase.update_coefficients!(W,uprev,p,t) # we will call `update_coefficients!` in NLNewton
    @label J2W
    W.transform = W_transform; set_gamma!(W, dtgamma)
  else # concrete W using jacobian from `calc_J!`
    new_jac && calc_J!(nlsolver, integrator, cache, is_compos)
    new_W && jacobian2W!(W, mass_matrix, dtgamma, J, W_transform)
  end
  if isnewton
    set_new_W!(nlsolver, new_W) && DiffEqBase.set_W_dt!(nlsolver, dt)
  end
  # new_W && (integrator.destats.nw += 1)
  return nothing
end

function calc_W!(nlsolver, integrator, cache::StochasticDiffEqConstantCache, dtgamma, repeat_step, W_transform=false)
  @unpack t,uprev,p,f = integrator
  @unpack uf = nlsolver
  mass_matrix = integrator.f.mass_matrix
  isarray = typeof(uprev) <: AbstractArray
  # calculate W
  uf.t = t
  is_compos = typeof(integrator.alg) <: StochasticCompositeAlgorithm
  if (f isa SDEFunction && islinear(f.f)) || (f isa SplitSDEFunction && islinear(f.f1.f))
    J = f.f1.f
    W = WOperator(mass_matrix, dtgamma, J, false; transform=W_transform)
  elseif DiffEqBase.has_jac(f)
    J = f.jac(uprev, p, t)
    if !isa(J, DiffEqBase.AbstractDiffEqLinearOperator)
      J = DiffEqArrayOperator(J)
    end
    W = WOperator(mass_matrix, dtgamma, J, false; transform=W_transform)
    # integrator.destats.nw += 1
  else
    # integrator.destats.nw += 1
    J = calc_J(nlsolver, integrator, cache, is_compos)
    W_full = W_transform ? -mass_matrix*inv(dtgamma) + J :
                           -mass_matrix + dtgamma*J
    W = W_full isa Number ? W_full : lu(W_full)
  end
  is_compos && (integrator.eigen_est = isarray ? opnorm(J, Inf) : J)
  J, W
end

# update W matrix (only used in Newton method)
update_W!(integrator, cache, dt, repeat_step) =
  update_W!(cache.nlsolver, integrator, cache, dt, repeat_step)

function update_W!(nlsolver::NLSolver, integrator, cache::StochasticDiffEqMutableCache, dt, repeat_step)
  if isnewton(nlsolver)
    calc_W!(nlsolver, integrator, cache, dt, repeat_step, true)
  end
  nothing
end

function update_W!(nlsolver::NLSolver, integrator, cache::StochasticDiffEqConstantCache, dt, repeat_step)
  if isnewton(nlsolver)
    J, W = calc_W!(nlsolver, integrator, cache, dt, repeat_step, true)
    DiffEqBase.set_W!(nlsolver, W)
    return J
  end
  nothing
end

iip_get_uf(alg::StochasticDiffEqAlgorithm,nf,t,p) = DiffEqDiffTools.UJacobianWrapper(nf,t,p)
oop_get_uf(alg::StochasticDiffEqAlgorithm,nf,t,p) = DiffEqDiffTools.UDerivativeWrapper(nf,t,p)
