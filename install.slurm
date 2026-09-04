#!/bin/bash -l
#SBATCH -J package_installation
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH --partition=msys
#SBATCH --exclude=msys2

echo "=== Loading R module ==="
module load r/4.1.3

PROJECT_DIR=$(pwd)
TMP_PKG_DIR="$PROJECT_DIR/build_tmp_pkgs"
ENV_DIR="$PROJECT_DIR/env"
VENV_DIR="$ENV_DIR/venv"
CLUSTERLEARN_DIR="$ENV_DIR/ClusterLearn"
PATCH_FILE="$PROJECT_DIR/R/predict.scope.logistic.R_patched"

mkdir -p "$TMP_PKG_DIR"
cd "$TMP_PKG_DIR"

# ==============================================================================
# 1. Download and install standard CRAN packages via wget & R CMD INSTALL
# ==============================================================================
echo "=== 1/4 Downloading PACKAGES file ==="

wget --no-check-certificate -O PACKAGES.gz https://cloud.r-project.org/src/contrib/PACKAGES.gz
gzip -dc PACKAGES.gz > PACKAGES

PKGS=(
  # Core helper libraries
  "R6" "RColorBrewer" "png" "rappdirs" "withr" "jsonlite" "RcppTOML"
  "rprojroot" "here" "abind" "Formula" "utf8" "fansi" "pkgconfig" "generics"

  # rlang / tidyverse ecosystem (required by modeldata and reticulate)
  "cli" "rlang" "glue" "magrittr" "lifecycle" "vctrs" "tidyselect"
  "pillar" "tibble" "purrr" "dplyr"

  # Statistics, plotting, and econometrics (required by DAAG and AER)
  "lattice" "latticeExtra" "zoo" "sandwich" "lmtest" "carData" "car"

  # Main CRAN and ML packages
  "Rcpp" "rbibutils" "Rdpack" "digest" "iterators" "foreach"
  "shape" "RcppEigen" "hclust1d" "glmnet" "ranger"
  "grpreg" "DMRnet" "randomForest" "DAAG" "wooldridge" "foreign"
  "AER" "modeldata" "reticulate"
)

for PKG in "${PKGS[@]}"; do
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
  R CMD INSTALL "${PKG}_${VER}.tar.gz"
done

# ==============================================================================
# 2. Download and install archived xgboost 1.7.8.1 (compatible with R 4.1.3)
# ==============================================================================
echo "=== 2/4 Downloading and installing archived xgboost 1.7.8.1 ==="

wget --no-check-certificate -O xgboost_1.7.8.1.tar.gz https://cloud.r-project.org/src/contrib/Archive/xgboost/xgboost_1.7.8.1.tar.gz
R CMD INSTALL xgboost_1.7.8.1.tar.gz

# ==============================================================================
# 3. Download, patch, and install CatReg 2.0.4
# ==============================================================================
echo "=== 3/4 Downloading, patching, and installing CatReg 2.0.4 ==="

wget --no-check-certificate -O CatReg_2.0.4.tar.gz https://cloud.r-project.org/src/contrib/CatReg_2.0.4.tar.gz || \
wget --no-check-certificate -O CatReg_2.0.4.tar.gz https://cloud.r-project.org/src/contrib/Archive/CatReg/CatReg_2.0.4.tar.gz

mkdir -p CatReg-src
tar -xzf CatReg_2.0.4.tar.gz -C CatReg-src
cp -v "$PATCH_FILE" CatReg-src/CatReg/R/predict.scope.logistic.R

R CMD build CatReg-src/CatReg
R CMD INSTALL CatReg_2.0.4.tar.gz

cd "$PROJECT_DIR"
rm -rf "$TMP_PKG_DIR"

# ==============================================================================
# 4. Setup Python virtual environment & compile ClusterLearn
# ==============================================================================
echo "=== 4/4 Setting up Python venv and compiling ClusterLearn ==="

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install numpy pandas scikit-learn gurobipy rpy2

if [ -d "$CLUSTERLEARN_DIR" ]; then
  rm -rf "$CLUSTERLEARN_DIR"
fi

git clone https://github.com/SzymonNowakowski/ClusterLearn.git "$CLUSTERLEARN_DIR"

cd "$CLUSTERLEARN_DIR/univariate"
EIGEN_INC=$(find /usr -type d -name "eigen3" 2>/devnull | head -n 1)

g++ -I"${EIGEN_INC:-/usr/include/eigen3}" -fPIC -std=c++17 -c *.cpp
g++ -shared -o proximal_c.so *.o

cd "$PROJECT_DIR"
echo "=== Installation finished successfully ==="