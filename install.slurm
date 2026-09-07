#!/bin/bash -l
#SBATCH -J package_installation
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH --partition=msys
#SBATCH --exclude=msys2

#SBATCH --output=install_%j.out
#SBATCH --error=install_%j.err

echo "=== Loading modules ==="
module load r/4.1.3

PROJECT_DIR=$(pwd)
TMP_PKG_DIR="$PROJECT_DIR/build_tmp_pkgs"
ENV_DIR="$PROJECT_DIR/env"
VENV_DIR="$ENV_DIR/venv"
CLUSTERLEARN_DIR="$ENV_DIR/ClusterLearn"
PATCH_FILE="$PROJECT_DIR/R/predict.scope.logistic.R_patched"

# Clean up any stale lock files
rm -rf ~/R/x86_64-pc-linux-gnu-library/4.1/00LOCK*

mkdir -p "$TMP_PKG_DIR"
cd "$TMP_PKG_DIR"

# ==============================================================================
# 1. Download and install core CRAN packages & reticulate dependencies
# ==============================================================================
echo "=== 1/4 Processing CRAN packages ==="

wget --no-check-certificate -O PACKAGES.gz https://cloud.r-project.org/src/contrib/PACKAGES.gz
gzip -dc PACKAGES.gz > PACKAGES

PKGS=(
  "png" "rappdirs" "withr" "jsonlite" "rlang" "RcppTOML" "rprojroot" "here"
  "Rcpp" "digest" "rbibutils" "Rdpack" "RcppEigen"
  "iterators" "foreach" "shape" "hclust1d"
  "glmnet" "grpreg" "DMRnet" "randomForest"
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
echo "=== 2/4 Processing CatReg 2.0.4 ==="

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
# 3. Clone ClusterLearn repository
# ==============================================================================
echo "=== 3/4 Cloning ClusterLearn repository ==="

mkdir -p "$ENV_DIR"
if [ -d "$CLUSTERLEARN_DIR" ]; then
  rm -rf "$CLUSTERLEARN_DIR"
fi
git clone https://github.com/SzymonNowakowski/ClusterLearn.git "$CLUSTERLEARN_DIR"

# ==============================================================================
# 4. Setup Miniconda Python (GLIBC 2.12 compatible) & compile C++
# ==============================================================================
echo "=== 4/4 Setting up Python environment and compiling ClusterLearn ==="

MINICONDA_DIR="$HOME/miniconda3"
if [ ! -d "$MINICONDA_DIR" ]; then
  echo "[INFO] Downloading Miniconda py39_4.9.2..."
  wget --no-check-certificate -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-py39_4.9.2-Linux-x86_64.sh
  bash miniconda.sh -b -p "$MINICONDA_DIR"
  rm miniconda.sh
fi

if [ -d "$VENV_DIR" ]; then
  rm -rf "$VENV_DIR"
fi

echo "[INFO] Creating venv from Miniconda base Python..."
"$MINICONDA_DIR/bin/python" -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

export R_HOME=$(R RHOME)
export LD_LIBRARY_PATH="$R_HOME/lib:$VENV_DIR/lib:$LD_LIBRARY_PATH"

pip install --upgrade "pip<24.0"
pip install --prefer-binary "numpy==1.21.6" "pandas<2.0.0" "rpy2<3.5.0" scikit-learn gurobipy

cd "$CLUSTERLEARN_DIR/univariate"
EIGEN_INC=$(find /usr -type d -name "eigen3" 2>/dev/null | head -n 1)

g++ -I"${EIGEN_INC:-/usr/include/eigen3}" -fPIC -std=c++17 -c *.cpp
g++ -shared -o proximal_c.so *.o

cd "$PROJECT_DIR"
echo "=== Installation finished successfully ==="