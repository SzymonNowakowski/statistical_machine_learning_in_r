#!/bin/bash -l

#SBATCH -J package_installation
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH --partition=msys
#SBATCH --exclude=msys2

set -e

# Load cluster R module
module load r/4.1.3

# Define isolated installation directory for Python/ClusterLearn
PROJECT_DIR=$(pwd)
ENV_DIR="$PROJECT_DIR/env"
VENV_DIR="$ENV_DIR/venv"
CLUSTERLEARN_DIR="$ENV_DIR/ClusterLearn"
WORKDIR="$PROJECT_DIR/build_tmp"

mkdir -p "$WORKDIR"

PATCH_FILE="$PROJECT_DIR/R/predict.scope.logistic.R_patched"
if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: Patch file not found at: $PATCH_FILE"
    exit 1
fi

# ==============================================================================
# 1. Install CRAN packages into default R library
# ==============================================================================
echo "=== 1/3 Installing R packages ==="

Rscript -e "
pkgs <- c(
  'xgboost', 'glmnet', 'ranger', 'grpreg', 'DMRnet',
  'randomForest', 'digest', 'DAAG', 'wooldridge',
  'foreign', 'carData', 'AER', 'modeldata', 'reticulate'
)
install.packages(pkgs, repos='https://cloud.r-project.org')
"

# ==============================================================================
# 2. Patch and install CatReg 2.0.4 into default R library
# ==============================================================================
echo "=== 2/3 Building patched CatReg ==="

cd "$WORKDIR"
wget -q https://cran.r-project.org/src/contrib/CatReg_2.0.4.tar.gz || \
wget -q https://cran.r-project.org/src/contrib/Archive/CatReg/CatReg_2.0.4.tar.gz

mkdir -p CatReg-src
tar -xzf CatReg_2.0.4.tar.gz -C CatReg-src
cp "$PATCH_FILE" CatReg-src/CatReg/R/predict.scope.logistic.R

R CMD build CatReg-src/CatReg
R CMD INSTALL CatReg_2.0.4.tar.gz
rm -rf CatReg-src CatReg_2.0.4.tar.gz

# ==============================================================================
# 3. Setup Python environment and compile ClusterLearn in local project directory
# ==============================================================================
echo "=== 3/3 Building ClusterLearn ==="

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install numpy pandas scikit-learn gurobipy rpy2

git clone https://github.com/SzymonNowakowski/ClusterLearn.git "$CLUSTERLEARN_DIR"
cd "$CLUSTERLEARN_DIR/univariate"

EIGEN_INC="/usr/include/eigen3"
if [ ! -d "$EIGEN_INC" ]; then
    EIGEN_INC=$(find /usr -type d -name "eigen3" 2>/dev/null | head -n 1)
fi

g++ -I"${EIGEN_INC:-/usr/include/eigen3}" -fPIC -std=c++17 -c *.cpp
g++ -shared -o proximal_c.so *.o

# Cleanup temporary build folder
cd "$PROJECT_DIR"
rm -rf "$WORKDIR"

echo "=== Installation finished ==="