#!/bin/bash -l

# Enable fail on error (-e)
set -euo pipefail

echo "======================================================================"
echo "[VERBOSE] Starting execution at $(date)"
echo "[VERBOSE] Working directory: $(pwd)"
echo "[VERBOSE] Running user: $(whoami)"
echo "[VERBOSE] Hostname: $(hostname)"
echo "======================================================================"

# Load cluster R module
echo "[VERBOSE] Loading R module..."
module load r/4.1.3
module list

# Define isolated installation directories
PROJECT_DIR=$(pwd)
ENV_DIR="$PROJECT_DIR/env"
VENV_DIR="$ENV_DIR/venv"
CLUSTERLEARN_DIR="$ENV_DIR/ClusterLearn"
WORKDIR="$PROJECT_DIR/build_tmp"
PATCH_FILE="$PROJECT_DIR/R/predict.scope.logistic.R_patched"

echo "[VERBOSE] Configuration paths:"
echo "  - PROJECT_DIR:      $PROJECT_DIR"
echo "  - ENV_DIR:          $ENV_DIR"
echo "  - VENV_DIR:         $VENV_DIR"
echo "  - CLUSTERLEARN_DIR: $CLUSTERLEARN_DIR"
echo "  - WORKDIR:          $WORKDIR"
echo "  - PATCH_FILE:       $PATCH_FILE"

# Create temporary build workspace verbosely
mkdir -pv "$WORKDIR"

if [ ! -f "$PATCH_FILE" ]; then
    echo "[ERROR] Patch file not found at: $PATCH_FILE" >&2
    exit 1
else
    echo "[VERBOSE] Found patch file at: $PATCH_FILE"
fi

# ==============================================================================
# 1. Install CRAN packages into default R library
# ==============================================================================
echo "======================================================================"
echo "[VERBOSE] 1/3 Installing R packages from CRAN..."
echo "======================================================================"

Rscript -e "
cat('[VERBOSE R] Initializing package installation...\n')
pkgs <- c(
  'xgboost', 'glmnet', 'ranger', 'grpreg', 'DMRnet',
  'randomForest', 'digest', 'DAAG', 'wooldridge',
  'foreign', 'carData', 'AER', 'modeldata', 'reticulate'
)
cat('[VERBOSE R] Target packages:\n')
print(pkgs)
install.packages(pkgs, repos='https://cloud.r-project.org', verbose=TRUE)
cat('[VERBOSE R] Package installation completed.\n')
"

# ==============================================================================
# 2. Patch and install CatReg 2.0.4 into default R library
# ==============================================================================
echo "======================================================================"
echo "[VERBOSE] 2/3 Building patched CatReg 2.0.4..."
echo "======================================================================"

cd "$WORKDIR"
echo "[VERBOSE] Changed directory to: $(pwd)"

echo "[VERBOSE] Downloading CatReg source archive..."
wget --verbose https://cran.r-project.org/src/contrib/CatReg_2.0.4.tar.gz || \
wget --verbose https://cran.r-project.org/src/contrib/Archive/CatReg/CatReg_2.0.4.tar.gz

mkdir -pv CatReg-src
echo "[VERBOSE] Extracting archive..."
tar -xzvf CatReg_2.0.4.tar.gz -C CatReg-src

echo "[VERBOSE] Applying patch file to predict.scope.logistic.R..."
cp -v "$PATCH_FILE" CatReg-src/CatReg/R/predict.scope.logistic.R

echo "[VERBOSE] Building patched R package..."
R CMD build CatReg-src/CatReg

echo "[VERBOSE] Installing R package from build tarball..."
R CMD INSTALL CatReg_2.0.4.tar.gz

echo "[VERBOSE] Cleaning up temporary CatReg sources..."
rm -rfv CatReg-src CatReg_2.0.4.tar.gz

# ==============================================================================
# 3. Setup Python environment and compile ClusterLearn
# ==============================================================================
echo "======================================================================"
echo "[VERBOSE] 3/3 Setting up Python venv and compiling ClusterLearn..."
echo "======================================================================"

echo "[VERBOSE] Creating virtual environment at: $VENV_DIR"
python3 -m venv "$VENV_DIR"

echo "[VERBOSE] Activating virtual environment..."
source "$VENV_DIR/bin/activate"

echo "[VERBOSE] Upgrading pip..."
pip install --verbose --upgrade pip

echo "[VERBOSE] Installing Python dependencies..."
pip install --verbose numpy pandas scikit-learn gurobipy rpy2

if [ -d "$CLUSTERLEARN_DIR" ]; then
    echo "[VERBOSE] Removing existing ClusterLearn folder..."
    rm -rfv "$CLUSTERLEARN_DIR"
fi

echo "[VERBOSE] Cloning ClusterLearn repository..."
git clone --verbose https://github.com/SzymonNowakowski/ClusterLearn.git "$CLUSTERLEARN_DIR"

cd "$CLUSTERLEARN_DIR/univariate"
echo "[VERBOSE] Changed directory to: $(pwd)"

EIGEN_INC="/usr/include/eigen3"
if [ ! -d "$EIGEN_INC" ]; then
    echo "[VERBOSE] Searching system for Eigen3 header directory..."
    EIGEN_INC=$(find /usr -type d -name "eigen3" 2>/dev/null | head -n 1)
fi
echo "[VERBOSE] Resolved Eigen3 include path: ${EIGEN_INC:-/usr/include/eigen3}"

echo "[VERBOSE] Compiling C++ source files with g++..."
g++ -I"${EIGEN_INC:-/usr/include/eigen3}" -fPIC -std=c++17 -c *.cpp -v

echo "[VERBOSE] Linking shared library proximal_c.so..."
g++ -shared -o proximal_c.so *.o -v

# Cleanup build workspace
cd "$PROJECT_DIR"
echo "[VERBOSE] Returning to project directory: $(pwd)"
echo "[VERBOSE] Removing temporary build directory..."
rm -rfv "$WORKDIR"

echo "======================================================================"
echo "[VERBOSE] Installation finished successfully at $(date)!"
echo "======================================================================"