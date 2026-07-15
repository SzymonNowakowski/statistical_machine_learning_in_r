########### port of https://github.com/mazumder-lab/ClusterLearn/blob/main/demo.py #############
################## Szymon Nowakowski assisted by Gemini ########################################


# ==============================================================================
# 1. Initialize Python Environment and Import Packages
# ==============================================================================
Sys.setenv(PYTHONWARNINGS = "ignore")
library(reticulate)

# Bind reticulate to our virtual environment
use_virtualenv("/opt/venv", required = TRUE)

# Import required modules from Python
np <- import("numpy")
utils <- import("utils") # Import utilities which contains both data generators and BCD_wrapper

# ==============================================================================
# 2. Simulation Parameters & Setup
# ==============================================================================
rng <- 0L
np$random$seed(rng)

n_cat <- 10L      # Number of categorical predictors
levels <- 12L     # Number of levels of each categorical predictor

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

X_cat0 <- data_gen[[1]]
X0 <- data_gen[[2]]
y0 <- data_gen[[3]]
beta_star <- data_gen[[4]]
groups <- data_gen[[5]]

# ==============================================================================
# 5. Split Dataset (Slicing Python arrays from R)
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
# 6. Tuning Parameter Grid
# ==============================================================================
n_lambda <- 10L
lambda1 <- np$logspace(-2, 2, n_lambda)
lambda0 <- np$logspace(-2, 2, n_lambda)

# ==============================================================================
# 7. Run Original BCD Wrapper through Python
# ==============================================================================
# Directly calling Python's original BCD_wrapper to run the compiled C++ engine
cat("Running original Python BCD_wrapper...\n")
bcd_results <- utils$BCD_wrapper(
  X_cat_train, y, X_cat_val, y_val, 
  numlevels_ = rep(levels, n_cat), 
  l0_list = rev(lambda0), 
  l1_list = rev(lambda1)
)

beta_bcd <- bcd_results[[1]]
time_bcd <- bcd_results[[2]]

# Split intercept and beta coefficients
intercept <- beta_bcd[length(beta_bcd)]
beta_bcd_coefs <- beta_bcd[-length(beta_bcd)]

# ==============================================================================
# 8. Calculate Performance Metrics
# ==============================================================================
metrics <- utils$performance_metrics(
  beta_bcd_coefs, beta_star, groups, y_test, X_test, intercept, mu = mean(y)
)

nnz        <- metrics[[1]]
pred       <- metrics[[2]]
purity     <- metrics[[4]]
purity_nnz <- metrics[[5]]
nclusters  <- metrics[[6]]

# Output results
cat("=========================================\n")
cat(sprintf("R2 on Test: %.4f\n", pred))
cat(sprintf("Number of Regression Coefficient Clusters: %d\n", as.integer(nclusters)))
cat(sprintf("NNZ Purity: %.4f\n", purity_nnz))
cat("=========================================\n")
