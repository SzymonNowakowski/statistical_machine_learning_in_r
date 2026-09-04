#!/bin/bash -l
#SBATCH -J package_installation
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH --partition=msys
#SBATCH --exclude=msys2

echo "=== Loading modules ==="
module load r/4.1.3
module load python/3.9.1

PROJECT_DIR=$(pwd)
TMP_PKG_DIR="$PROJECT_DIR/build_tmp_pkgs"
ENV_DIR="$PROJECT_DIR/env"
VENV_DIR="$ENV_DIR/venv"
CLUSTERLEARN_DIR="$ENV_DIR/ClusterLearn"
PATCH_FILE="$PROJECT_DIR/R/predict.scope.logistic.R_patched"

# Clean up any stale lock files from previous runs
rm -rf ~/R/x86_64-pc-linux-gnu-library/4.1/00LOCK*

mkdir -p "$TMP_PKG_DIR"
cd "$TMP_PKG_DIR"

# ==============================================================================
# 1. Download and install core CRAN packages & reticulate dependencies
# ==============================================================================
echo "=== 1/3 Processing CRAN packages ==="

wget --no-check-certificate -O PACKAGES.gz https://cloud.r-project.org/src/contrib/PACKAGES.gz
gzip -dc PACKAGES.gz > PACKAGES

# Minimal dependency chain ordered by build hierarchy
PKGS=(
  # Explicit dependencies for reticulate
  "png" "rappdirs" "withr" "jsonlite" "rlang" "RcppTOML" "rprojroot" "here"

  # Core tools & C++ headers
  "Rcpp" "digest" "rbibutils" "Rdpack" "RcppEigen"

  # Iterators & math helper packages
  "iterators" "foreach" "shape" "hclust1d"

  # Primary machine learning packages
  "glmnet" "grpreg" "DMRnet" "randomForest"

  # Python integration package
  "reticulate"
)

for PKG in "${PKGS[@]}"; do
  if Rscript -e "if (!requireNamespace('$PKG', quietly = TRUE)) quit(status = 1)" >/dev/null 2>&1; then
    echo "[INFO] $PKG is already installed. Skipping."
    continue
  fi

  VER=$(awk -v P="$PKG" '
    $0=="Package: "P {p=1; next}
    p && $1=="Version:" {print $2; exit}
    p && $0=="" {p=0}
  ' PACKAGES)

  if [ -z "$VER" ]; then
    echo "[ERROR] Cannot find version for $PKG in PACKAGES"
    continue
  fi

  echo "[INFO] Downloading $PKG ($VER)..."
  wget --no-check-certificate -O "${PKG}_${VER}.tar.gz" "https://cloud.r-project.org/src/contrib/${PKG}_${VER}.tar.gz"

  echo "[INFO] Installing $PKG ($VER)..."
  R CMD INSTALL --no-lock "${PKG}_${VER}.tar.gz"
done

# ==============================================================================
# 2. Download, patch, and install CatReg 2.0.4
# ==============================================================================
echo "=== 2/3 Processing CatReg 2.0.4 ==="

if Rscript -e "if (!requireNamespace('CatReg', quietly = TRUE)) quit(status = 1)" >/dev/null 2>&1; then
  echo "[INFO] CatReg is already installed. Skipping."
else
  echo "[INFO] Downloading, patching, and installing CatReg 2.0.4..."
  wget --no-check-certificate -O CatReg_2.0.4.tar.gz https://cloud.r-project.org/src/contrib/CatReg_2.0.4.tar.gz || \
  wget --no-check-certificate -O CatReg_2.0.4.tar.gz https://cloud.r-project.org/src/contrib/Archive/CatReg/CatReg_2.0.4.tar.gz

  mkdir -p CatReg-src
  tar -xzf CatReg_2.0.4.tar.gz -C CatReg-src
  cp -v "$PATCH_FILE" CatReg-src/CatReg/R/predict.scope.logistic.R

  R CMD build CatReg-src/CatReg
  R CMD INSTALL --no-lock CatReg_2.0.4.tar.gz
fi

cd "$PROJECT_DIR"
rm -rf "$TMP_PKG_DIR"

# ==============================================================================
# 3. Setup Python virtual environment & compile ClusterLearn
# ==============================================================================
echo "=== 3/3 Setting up Python venv and compiling ClusterLearn ==="

# Set R environment variables required by rpy2
export R_HOME=$(R RHOME)
export LD_LIBRARY_PATH="$R_HOME/lib:$LD_LIBRARY_PATH"

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

pip install --upgrade pip

# Pin rpy2 < 3.5.0 and numpy 1.23.5 for R 4.1.3 & GCC compatibility
pip install --prefer-binary "numpy==1.23.5" "pandas<2.0.0" "rpy2<3.5.0" scikit-learn gurobipy

if [ -d "$CLUSTERLEARN_DIR" ]; then
  rm -rf "$CLUSTERLEARN_DIR"
fi

git clone https://github.com/SzymonNowakowski/ClusterLearn.git "$CLUSTERLEARN_DIR"

cd "$CLUSTERLEARN_DIR/univariate"
EIGEN_INC=$(find /usr -type d -name "eigen3" 2>/dev/null | head -n 1)

g++ -I"${EIGEN_INC:-/usr/include/eigen3}" -fPIC -std=c++17 -c *.cpp
g++ -shared -o proximal_c.so *.o

cd "$PROJECT_DIR"
echo "=== Installation finished successfully ==="