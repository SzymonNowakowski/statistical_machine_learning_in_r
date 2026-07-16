########### port of https://github.com/mazumder-lab/ClusterLearn/blob/main/demo_exact.py #############
################## Szymon Nowakowski assisted by Gemini ########################################
# ==============================================================================
# 1. Konfiguracja Środowiska i Import Modułów Pythona
# ==============================================================================
library(reticulate)

# Wskazanie wirtualnego środowiska Pythona z kontenera
use_virtualenv("/opt/venv", required = TRUE)

# Import bibliotek Pythona
np      <- import("numpy")
utils   <- import("utils")
mip_core <- import("MIPSolver.core")

# Ustawienie ziarna losowości
rng <- 0L
np$random$seed(rng)
set.seed(rng)

# ==============================================================================
# 2. Parametry i Generowanie beta_star
# ==============================================================================
n_cat  <- 5L
levels <- 15L

# Odpowiednik Pythonowego bloku [-2]*4 + [0]*(15-8) + [2]*4
beta_block <- c(rep(-2, 4), rep(0, levels - 8), rep(2, 4))

# Pierwsze dwie cechy otrzymują powyższy wzorzec, reszta otrzymuje zera
beta <- c(beta_block, beta_block, rep(0, (n_cat - 2L) * levels))
beta_double <- as.numeric(beta) # rzutowanie na typ float/double

# ==============================================================================
# 3. Generowanie Dane wejściowych (Draw the data)
# ==============================================================================
n <- 500L
noise_sigma <- 1.0
rho <- 0.2

# Macierz kowariancji w R: (1-rho)*I + rho*1
cov_mat <- diag(1 - rho, n_cat) + matrix(rho, n_cat, n_cat)

# Wywołanie generatora z utils.py
# Przekazujemy 3*n dla pełnego zbioru (Train + Val + Test)
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

# Rozpakowanie wyników (zwracanych jako krotka z Pythona)
X_cat0    <- generated_data[[1]]
X0        <- generated_data[[2]]
y0        <- generated_data[[3]]
beta_star <- generated_data[[4]]
groups    <- generated_data[[5]]

# ==============================================================================
# 4. Podział Danych (Train / Validation / Test)
# ==============================================================================
# Uwzględniamy 1-indeksowanie w R:
# Python 0:n     -> R 1:n
# Python n:2*n   -> R (n+1):(2*n)
# Python 2*n:3*n -> R (2*n+1):(3*n)

# Dane zdyskretyzowane (Dummified):
X      <- X0[1:n, ]
X_val  <- X0[(n + 1):(2 * n), ]
X_test <- X0[(2 * n + 1):(3 * n), ]

# Dane kategoryczne (Factors):
X_cat_train <- X_cat0[1:n, ]
X_cat_val   <- X_cat0[(n + 1):(2 * n), ]
X_cat_test  <- X_cat0[(2 * n + 1):(3 * n), ]

# Wektory odpowiedzi (Targets):
y      <- y0[1:n]
y_val  <- y0[(n + 1):(2 * n)]
y_test <- y0[(2 * n + 1):(3 * n)]

# ==============================================================================
# 5. BCD Warm-start Solver
# ==============================================================================
lambda1 <- 0.05
lambda0 <- 0.05

# l0_list, l1_list, l2_list muszą być przekazane jako wektory float
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
# 6. Metryki dla BCD
# ==============================================================================
# beta_bcd ma rozmiar p+1 (ostatni element to intercept)
p <- length(beta_bcd) - 1
beta_bcd_no_intercept <- beta_bcd[1:p]
intercept_bcd         <- beta_bcd[p + 1]

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
# 7. MIP Solver (Gurobi)
# ==============================================================================
# Obliczenie parametru M (Big-M)
M <- 1.2 * max(abs(beta_bcd_no_intercept))

# Inicjalizacja klasy MIPSolver z modułu Python
mip_solver <- mip_core$MIPSolver(
  X = X,
  y = y,
  l0 = lambda0,
  l1 = lambda1,
  groups = groups,
  beta0 = beta_bcd,
  M = M
)

# Uruchomienie wyszukiwania optymalnego rozwiązania (Row Generation)
mip_res <- mip_solver$GRB_rowgen()

beta_mip <- mip_res[[1]]
mu_mip   <- mip_res[[2]]
obj_mip  <- mip_res[[3]]
gap      <- mip_res[[4]]

# Metryki dla MIP
metrics_mip <- utils$performance_metrics(
  beta_mip,
  beta_star,
  groups,
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
# 8. Prezentacja Wyników (Console Output)
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