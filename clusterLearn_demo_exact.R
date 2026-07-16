########### port of https://github.com/mazumder-lab/ClusterLearn/blob/main/demo_exact.py #############
################## Szymon Nowakowski assisted by Gemini ########################################
# ==============================================================================
# 1. Environment Setup and Python Module Imports
# ==============================================================================
library(reticulate)

# Bind reticulate to our virtual environment inside the container
use_virtualenv("/opt/venv", required = TRUE)

# Import required modules from Python (default convert = TRUE)
np       <- import("numpy")
utils    <- import("utils")
mip_core <- import("MIPSolver.core")

# Set random seeds for reproducibility
rng <- 0L
np$random$seed(rng)
set.seed(rng)

# ==============================================================================
# 2. Simulation Parameters & Setup
# ==============================================================================
n_cat  <- 10L      # Number of categorical predictors
levels <- 12L      # Number of levels of each categorical predictor

# ==============================================================================
# 3. Create true beta^*
# ==============================================================================
# Build structured coefficient beta in R
beta <- list()
for (j in 1:2) {
  beta <- c(beta, rep(-2, 4), rep(0, levels - 8), rep(2, 4))
}
# Pad remaining categories with zero
beta <- c(beta, rep(0, n_cat * levels - 2 * levels))
beta <- as.numeric(beta)

# ==============================================================================
# 4. Generate Random Correlated Data
# ==============================================================================
n <- 100L               # Number of train/test/validation data points
noise_sigma <- 1.0
rho <- 0.2

# Pairwise correlation matrix
cov_mat <- (1 - rho) * diag(n_cat) + rho * matrix(1, nrow = n_cat, ncol = n_cat)

# Generate dataset using Python's utility
data_gen <- utils$generate_random_correlated(
  as.integer(3 * n), cov_mat, as.integer(levels),
  RNG = rng, noise_sigma = noise_sigma,
  sparsity = 0L, clustering = 0L, beta = as.list(beta)
)

X_cat0    <- data_gen[[1]]
X0        <- data_gen[[2]]
y0        <- data_gen[[3]]
beta_star <- data_gen[[4]]
groups    <- data_gen[[5]]

# ==============================================================================
# 5. Split Dataset (Slicing native R arrays)
# ==============================================================================
# Dummy matrices:
X      <- X0[1:n, ]
X_val  <- X0[(n + 1):(2 * n), ]
X_test <- X0[(2 * n + 1):(3 * n), ]

# Categorical factor matrices:
X_cat_train <- X_cat0[1:n, ]
X_cat_val   <- X_cat0[(n + 1):(2 * n), ]
X_cat_test  <- X_cat0[(2 * n + 1):(3 * n), ]

# Target variables:
y      <- y0[1:n]
y_val  <- y0[(n + 1):(2 * n)]
y_test <- y0[(2 * n + 1):(3 * n)]

# ==============================================================================
# 6. Tuning Parameters
# ==============================================================================
lambda1 <- 0.05
lambda0 <- 0.05

# ==============================================================================
# 7. Run Original BCD Wrapper (Warm-start)
# ==============================================================================
cat("Running BCD Solver...\n")

# Wrap single values into 1D NumPy arrays to satisfy BCD_wrapper's sequence checks
l0_list_py <- np$array(c(lambda0))
l1_list_py <- np$array(c(lambda1))
l2_list_py <- np$array(c(0.0))

bcd_results <- utils$BCD_wrapper(
  X = X_cat_train,
  y = y,
  Xval = X_cat_val,
  yval = y_val,
  numlevels_ = as.integer(rep(levels, n_cat)),
  l0_list = l0_list_py,
  l1_list = l1_list_py,
  l2_list = l2_list_py
)

beta_bcd <- bcd_results[[1]]
time_bcd <- bcd_results[[2]]

# Split intercept and beta coefficients
intercept_bcd         <- beta_bcd[length(beta_bcd)]
beta_bcd_no_intercept <- beta_bcd[-length(beta_bcd)]

# Performance metrics for BCD
metrics_bcd <- utils$performance_metrics(
  beta_bcd_no_intercept, beta_star, groups, y_test, X_test, intercept_bcd, mu = mean(y)
)

pred_bcd       <- metrics_bcd[[2]]
purity_nnz_bcd <- metrics_bcd[[5]]

# ==============================================================================
# 8. MIP Solver (Gurobi Exact Solver) Execution
# ==============================================================================
cat("Running Exact MIP Solver via Gurobi...\n")

# Calculate Big-M bound and cast parameters as explicit floats
M_val     <- as.numeric(1.2 * max(abs(beta_bcd_no_intercept)))
l0_scalar <- as.numeric(lambda0)
l1_scalar <- as.numeric(lambda1)

# Initialize and fit the MIPSolver class
mip_solver <- mip_core$MIPSolver(
  X = X,
  y = y,
  lambda0 = l0_scalar,
  lambda1 = l1_scalar,
  groups = groups,
  beta0 = beta_bcd,
  M = M_val
)

mip_res <- mip_solver$GRB_rowgen()

beta_mip <- mip_res[[1]]
mu_mip   <- mip_res[[2]]
obj_mip  <- mip_res[[3]]
gap      <- mip_res[[4]]

# Performance metrics for the Exact MIP Solver
metrics_mip <- utils$performance_metrics(
  beta_mip, beta_star, groups, y_test, X_test, mu_mip, mu = mean(y)
)

pred_mip       <- metrics_mip[[2]]
purity_nnz_mip <- metrics_mip[[5]]

# ==============================================================================
# 9. Display Comparative Results
# ==============================================================================
cat("\n==================================================\n")
cat("MIP results:\n")
cat(sprintf("R2 on Test:  %.4f\n", pred_mip))
cat(sprintf("Objective:   %.4f\n", obj_mip))
cat(sprintf("NNZ Purity:  %.4f\n", purity_nnz_mip))
cat("==================================================\n")
cat("BCD results:\n")
cat(sprintf("R2 on Test:  %.4f\n", pred_bcd))
cat(sprintf("Objective:   %.4f\n", mip_solver$objective(beta_bcd_no_intercept, intercept_bcd)))
cat(sprintf("NNZ Purity:  %.4f\n", purity_nnz_bcd))
cat("==================================================\n")