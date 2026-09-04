#!/bin/bash -l
#SBATCH -J package_installation
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH --partition=msys
#SBATCH --exclude=msys2

set -euo pipefail

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
# 1. Download and install CRAN packages via wget & R CMD INSTALL
# ==============================================================================
echo "=== 1/3 Downloading and installing CRAN packages ==="

wget --no-check-certificate -O PACKAGES.gz https://cloud.r-project.org/src/contrib/PACKAGES.gz

# Lista zależności oraz docelowych pakietów w kolejności budowania
PKGS=(
  "Rcpp" "rbibutils" "Rdpack" "digest" "iterators" "foreach"
  "shape" "RcppEigen" "hclust1d" "xgboost" "glmnet" "ranger"
  "grpreg" "DMRnet" "randomForest" "DAAG" "wooldridge" "foreign"
  "carData" "AER" "modeldata" "reticulate"
)

for PKG in "${PKGS[@]}"; do
  VER=$(gzip -dc PACKAGES.gz | awk -v P="$PKG" '
    $0=="Package: "P{p=1; next}
    p && $1=="Version:"{print $2; exit}
    p && $0==""{p=0}
  ')

  if [ -z "$VER" ]; then
    echo "[ERROR] Cannot find version for $PKG in PACKAGES.gz"
    exit 1
  fi

  echo "[INFO] Downloading $PKG ($VER)..."
  wget -q -O "${PKG}_${VER}.tar.gz" "https://cloud.r-project.org/src/contrib/${PKG}_${VER}.tar.gz"

  echo "[INFO] Installing $PKG ($VER)..."
  R CMD INSTALL "${PKG}_${VER}.tar.gz"
done

# ==============================================================================
# 2. Download, patch, and install CatReg 2.0.4
# ==============================================================================
echo "=== 2/3 Downloading, patching, and installing CatReg 2.0.4 ==="

wget -q -O CatReg_2.0.4.tar.gz https://cloud.r-project.org/src/contrib/CatReg_2.0.4.tar.gz || \
wget -q -O CatReg_2.0.4.tar.gz https://cloud.r-project.org/src/contrib/Archive/CatReg/CatReg_2.0.4.tar.gz

mkdir -p CatReg-src
tar -xzf CatReg_2.0.4.tar.gz -C CatReg-src
cp -v "$PATCH_FILE" CatReg-src/CatReg/R/predict.scope.logistic.R

R CMD build CatReg-src/CatReg
R CMD INSTALL CatReg_2.0.4.tar.gz

cd "$PROJECT_DIR"
rm -rf "$TMP_PKG_DIR"

# ==============================================================================
# 3. Setup Python virtual environment & compile ClusterLearn
# ==============================================================================
echo "=== 3/3 Setting up Python venv and compiling ClusterLearn ==="

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install numpy pandas scikit-learn gurobipy rpy2

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