using StochasticDiffEq, DiffEqDevTools, Test, LinearAlgebra
Random.seed!(100)
dts = (1/2) .^ (10:-1:2) #14->7 good plot

const σ_const = 0.87
const μ = 1.01

u0 = rand(2)
A = [-2.0 1.0;1.0 -2.0]
B = Diagonal([σ_const for i in 1:2])

function f_commute(du,u,p,t)
  mul!(du,A,u)
  du .+= 1.01u
end

function f_commute_analytic(u0,p,t,W)
 tmp = (A+1.01I-(B^2))*t + B*sum(W)
 exp(tmp)*u0
end

function σ(du,u,p,t)
  du[1,1] = σ_const*u[1]
  du[1,2] = σ_const*u[1]
  du[2,1] = σ_const*u[2]
  du[2,2] = σ_const*u[2]
end

ff_commute = SDEFunction(f_commute,σ,analytic=f_commute_analytic)

prob = SDEProblem(ff_commute,σ,u0,(0.0,1.0),noise_rate_prototype=rand(2,2))

sol = solve(prob,RKMilCommute(),dt=1/2^(8))
sol = solve(prob,EM(),dt=1/2^(10))

dts = (1/2) .^ (10:-1:3) #14->7 good plot
sim2 = test_convergence(dts,prob,EM(),numMonte=Int(1e2))
sim2 = test_convergence(dts,prob,RKMilCommute(),numMonte=Int(1e2))

sim2.𝒪est[:final] - 1 < 0.2
