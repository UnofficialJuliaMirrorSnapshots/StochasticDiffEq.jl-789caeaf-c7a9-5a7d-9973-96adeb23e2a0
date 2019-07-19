using StochasticDiffEq, Test, Random, DiffEqDevTools
using DiffEqProblemLibrary.SDEProblemLibrary: importsdeproblems; importsdeproblems()
using DiffEqProblemLibrary.SDEProblemLibrary: prob_sde_2Dlinear
Random.seed!(100)
prob = prob_sde_2Dlinear

## Solve and plot
println("Solve and Plot")
sol = solve(prob,EM(),dt=1/2^(3))
sol = solve(prob,LambaEM(),dt=1/2^(3))
sol = solve(prob,LambaEulerHeun(),dt=1/2^(3))
sol = solve(prob,RKMil(),dt=1/2^(3))
sol = solve(prob,SRI(),dt=1/2^(3))
sol = solve(prob,SRIW1(),dt=1/2^(3))
sol = solve(prob,SRIW2(),dt=1/2^(3))
sol = solve(prob,SOSRI(),dt=1/2^(3))
sol = solve(prob,SOSRI2(),dt=1/2^(3))
sol = solve(prob,ImplicitEM(),dt=1/2^(3))
sol = solve(prob,ImplicitEM(nlsolve=StochasticDiffEq.NLFunctional()),dt=1/2^(3),adaptive=false)
sol = solve(prob,ImplicitEM(autodiff=false),dt=1/2^(3))
sol = solve(prob,ImplicitRKMil(),dt=1/2^(3))

sol = solve(prob,SRIW1(),dt=1/2^(3),save_everystep=false)
#sol = solve(prob,SRIW1(),dt=1/2^(3),progress=true,progress_steps=1)

sol = solve(prob,SRIW1(),dt=1/2^(3),seed=1)
sol2 = solve(prob,SRI(error_terms=2),dt=1/2^(3),seed=1,delta=1/6)
sol.t ≈ sol2.t

sol2 = solve(prob,SRI(tableau=StochasticDiffEq.constructSRIOpt1()),dt=1/2^(3),seed=1)
sol = solve(prob,SOSRI(),dt=1/2^(3),seed=1)
sol.t ≈ sol2.t

## Convergence Testing
println("Convergence Test on 2D Linear")
dts = (1/2) .^ (7:-1:4) #14->7 good plot

sim = test_convergence(dts,prob,EM(),trajectories=1000)
@test abs(sim.𝒪est[:l2]-.5) < 0.1

sim = test_convergence(dts,prob,LambaEM(),trajectories=1000)
@test abs(sim.𝒪est[:l2]-.5) < 0.1

sim = test_convergence(dts,prob,ImplicitEM(),trajectories=300)
@test abs(sim.𝒪est[:l2]-.5) < 0.1

sim = test_convergence(dts,prob,ImplicitEM(theta=1),trajectories=100)
@test abs(sim.𝒪est[:l2]-.5) < 0.1

sim = test_convergence(dts,prob,ImplicitEM(symplectic=true),trajectories=500)
@test abs(sim.𝒪est[:l2]-.5) < 0.1

sim = test_convergence(dts,prob,ImplicitEM(symplectic=true,autodiff=false),trajectories=100)
@test abs(sim.𝒪est[:l2]-.5) < 0.1

sim = test_convergence(dts,prob,ISSEM(),trajectories=100)
@test abs(sim.𝒪est[:l2]-.5) < 0.1

sim = test_convergence(dts,prob,ImplicitRKMil(),trajectories=100)
@test abs(sim.𝒪est[:l2]-1) < 0.1

sim = test_convergence(dts,prob,ImplicitRKMil(theta=1),trajectories=100)
@test abs(sim.𝒪est[:l2]-1) < 0.1

sim = test_convergence(dts,prob,ImplicitRKMil(theta=1,autodiff=false),trajectories=200)
@test abs(sim.𝒪est[:l2]-1) < 0.1

sim = test_convergence(dts,prob,ImplicitRKMil(symplectic=true),trajectories=150)
@test abs(sim.𝒪est[:l2]-1) < 0.1

sim = test_convergence(dts,prob,ImplicitRKMil(symplectic=true,autodiff=false),trajectories=100)
@test abs(sim.𝒪est[:l2]-1) < 0.1

sim = test_convergence(dts,prob,ImplicitRKMil(nlsolve=StochasticDiffEq.NLFunctional()),trajectories=100)
@test abs(sim.𝒪est[:l2]-1) < 0.1

sim2 = test_convergence(dts,prob,RKMil(),trajectories=1000)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

print(".")

sim2 = test_convergence(dts,prob,WangLi3SMil_A(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,WangLi3SMil_B(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,WangLi3SMil_C(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,WangLi3SMil_D(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,WangLi3SMil_E(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,WangLi3SMil_F(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

print(".")

sim2 = test_convergence(dts,prob,SROCK1(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,SROCK2(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,SROCKEM(strong_order_1=false),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-0.5) < 0.2

sim2 = test_convergence(dts,prob,SROCKEM(),trajectories=100)
@test abs(sim2.𝒪est[:l∞]-1) < 0.2

sim2 = test_convergence(dts,prob,SKSROCK(),trajectories=500)
@test abs(sim2.𝒪est[:l∞]-0.5) < 0.2

# #omitting tests for incomplete methods
# sim = test_convergence(dts,prob,TangXiaoSROCK2(version_num=1),trajectories=100)
# @test abs(sim.𝒪est[:l∞]- 1) < 0.2
#
# sim = test_convergence(dts,prob,TangXiaoSROCK2(version_num=2),trajectories=100)
# @test abs(sim.𝒪est[:l∞]- 1) < 0.2
#
# sim = test_convergence(dts,prob,TangXiaoSROCK2(version_num=3),trajectories=100)
# @test abs(sim.𝒪est[:l∞]- 1) < 0.2
#
# sim = test_convergence(dts,prob,TangXiaoSROCK2(version_num=4),trajectories=100)
# @test abs(sim.𝒪est[:l∞]- 1) < 0.2
#
# sim = test_convergence(dts,prob,TangXiaoSROCK2(version_num=5),trajectories=100)
# @test abs(sim.𝒪est[:l∞]- 1) < 0.2

print(".")

sim3 = test_convergence(dts,prob,SRI(),trajectories=10)
@test abs(sim3.𝒪est[:final]-1.5) < 0.3

sim4 = test_convergence(dts,prob,SRIW1(),trajectories=100)
@test abs(sim4.𝒪est[:final]-1.5) < 0.3

sim4 = test_convergence(dts,prob,SRIW2(),trajectories=100)
@test abs(sim4.𝒪est[:final]-1.5) < 0.3

sim4 = test_convergence(dts,prob,SOSRI(),trajectories=100)
@test abs(sim4.𝒪est[:final]-1.5) < 0.3

sim4 = test_convergence(dts,prob,SOSRI2(),trajectories=100)
@test abs(sim4.𝒪est[:final]-1.5) < 0.3

# 2D oop
f_oop(u,p,t) = u
g_oop(u,p,t) = u
prob = SDEProblem(f_oop, g_oop, ones(2, 2), (0., 1.))
@test_nowarn solve(prob, ImplicitEM())
