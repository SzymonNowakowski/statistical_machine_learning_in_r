########### port of https://github.com/mazumder-lab/ClusterLearn/blob/main/demo_exact.py #############
################## Szymon Nowakowski assisted by Gemini ########################################
# ==============================================================================
# 1. Environment Setup and Python Module Imports
# ==============================================================================
library(reticulate)

# Point reticulate to the Python virtual environment inside the container
use_virtualenv("/opt/venv", required = TRUE)

# Import required Python packages
np       <- import("numpy")
utils    <- import("utils", convert = FALSE)
mip_core <- import("MIPSolver.core")

# Set random seeds for reproducibility
rng <- 0L
np$random$seed(rng)
set.seed(rng)

# ==============================================================================
# 2. Parameters and Beta Star Configuration
# ==============================================================================
n_cat  <- 5L
levels <- 15L

# Equivalent to Python's: [-2]*4 + [0]*(15-8) + [2]*4
beta_block <- c(rep(-2, 4), rep(0, levels - 8), rep(2, 4))

# First two features get the block pattern, the rest get zeros
beta <- c(beta_block, beta_block, rep(0, (n_cat - 2L) * levels))
beta_double <- as.numeric(beta) # Explicitly cast to double/float

# ==============================================================================
# 3. Data Generation
# ==============================================================================
n <- 500L
noise_sigma <- 1.0
rho <- 0.2

# Build the pairwise correlation matrix in R: (1-rho)*I + rho*1
cov_mat <- diag(1 - rho, n_cat) + matrix(rho, n_cat, n_cat)

# Generate synthetic dataset using utils.py (3 * n to cover Train, Val, and Test)
generated_data <- utils$generate_random_correlated(
  n = as.integer(3 * n),
  cov_mat = cov_mat,
  num_levels = as.integer(levels),
  RNG = rng,
  noise_sigma = noise_sigma,
  sparsity = 0.0,
  clustering = 0.0,
  beta = beta_double
)
print(py_to_r(generated_data[[5]]))
str(py_to_r(generated_data[[5]]))

# Unpack the generated tuple from Python
X_cat0    <- generated_data[[1]]
X0        <- generated_data[[2]]
y0        <- generated_data[[3]]
beta_star <- generated_data[[4]]
py_groups <- generated_data[[5]]

# ==============================================================================
# 4. Train / Validation / Test Splitting
# ==============================================================================
# Adjusting for R's 1-based indexing:
# Python 0:n     -> R 1:n
# Python n:2*n   -> R (n+1):(2*n)
# Python 2*n:3*n -> R (2*n+1):(3*n)

# Dummified design matrices:
X      <- X0[1:n, ]
X_val  <- X0[(n + 1):(2 * n), ]
X_test <- X0[(2 * n + 1):(3 * n), ]

# Categorical factor matrices:
X_cat_train <- X_cat0[1:n, ]
X_cat_val   <- X_cat0[(n + 1):(2 * n), ]
X_cat_test  <- X_cat0[(2 * n + 1):(3 * n), ]

# Target vectors:
y      <- y0[1:n]
y_val  <- y0[(n + 1):(2 * n)]
y_test <- y0[(2 * n + 1):(3 * n)]

# ==============================================================================
# 5. BCD Warm-start Solver Execution
# ==============================================================================
lambda1 <- 0.05
lambda0 <- 0.05

# Run BCD solver via utils.py wrapper
bcd_res <- utils$BCD_wrapper(
  X = X_cat_train,
  y = y,
  Xval = X_cat_val,
  yval = y_val,
  numlevels_ = as.integer(rep(levels, n_cat)),
  l0_list = np$flip(c(lambda0)),
  l1_list = np$flip(c(lambda1)),
  l2_list = np$flip(c(0.0))
)

beta_bcd <- bcd_res[[1]]
time_bcd <- bcd_res[[2]]

# ==============================================================================
# 6. Performance Metrics for BCD
# ==============================================================================
# beta_bcd has size p+1 (the last element is the intercept)
p <- length(beta_bcd) - 1
beta_bcd_no_intercept <- beta_bcd[1:p]
intercept_bcd         <- beta_bcd[p + 1]

# Calculate metrics using utils.py helper
metrics_bcd <- utils$performance_metrics(
  beta_bcd_no_intercept,
  beta_star,
  groups,
  y_test,
  X_test,
  intercept_bcd,
  mu = mean(y)
)

nnz_bcd         <- metrics_bcd[[1]]
pred_bcd        <- metrics_bcd[[2]]
purity_bcd      <- metrics_bcd[[4]]
purity_nnz_bcd  <- metrics_bcd[[5]]
nclusters_bcd   <- metrics_bcd[[6]]

# ==============================================================================
# 7. MIP Solver (Gurobi) Execution
# ==============================================================================
# Calculate Big-M bound and cast to a clean R numeric
M_val <- as.numeric(1.2 * max(abs(beta_bcd_no_intercept)))

l0_scalar <- as.numeric(lambda0)
l1_scalar <- as.numeric(lambda1)

# Initialize the MIPSolver class with the pure Python 'py_groups' reference
mip_solver <- mip_core$MIPSolver(
  X = X,
  y = y,
  lambda0 = l0_scalar,
  lambda1 = l1_scalar,
  groups = py_groups, # Native Python object, zero conversion issues!
  beta0 = beta_bcd,
  M = M_val
)

# Solve the mixed integer program using row generation
mip_res <- mip_solver$GRB_rowgen()

beta_mip <- mip_res[[1]]
mu_mip   <- mip_res[[2]]
obj_mip  <- mip_res[[3]]
gap      <- mip_res[[4]]

# Calculate performance metrics for the exact MIP solver
metrics_mip <- utils$performance_metrics(
  beta_mip,
  beta_star,
  py_groups,
  y_test,
  X_test,
  mu_mip,
  mu = mean(y)
)

nnz        <- metrics_mip[[1]]
pred       <- metrics_mip[[2]]
purity     <- metrics_mip[[4]]
purity_nnz <- metrics_mip[[5]]
nclusters  <- metrics_mip[[6]]

# ==============================================================================
# 8. Display Results
# ==============================================================================
cat("\n==================================================\n")
cat("MIP results:\n")
cat("R2 on Test:  ", pred, "\n")
cat("Objective:   ", obj_mip, "\n")
cat("NNZ Purity:  ", purity_nnz, "\n")
cat("==================================================\n")
cat("BCD results:\n")
cat("R2 on Test:  ", pred_bcd, "\n")
cat("Objective:   ", mip_solver$objective(beta_bcd_no_intercept, intercept_bcd), "\n")
cat("NNZ Purity:  ", purity_nnz_bcd, "\n")
cat("==================================================\n")