#!/bin/bash -l
#SBATCH -J clusterlearn_demo
#SBATCH --cpus-per-task=1
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH --partition=msys
#SBATCH --exclude=msys2
#SBATCH --output=demo_%j.out
#SBATCH --error=demo_%j.err

echo "=== Loading modules ==="
module load r/4.1.3

echo "=== Setting up environment ==="
PROJECT_DIR=$(pwd)
VENV_DIR="$PROJECT_DIR/env/venv"

# Aktywacja środowiska Conda utworzonego w skrypcie instalacyjnym
source "$HOME/miniconda3/bin/activate"
conda activate "$VENV_DIR"

# Konfiguracja zmiennych środowiskowych dla R i reticulate
export R_HOME=$(R RHOME)
export LD_LIBRARY_PATH="$R_HOME/lib:$VENV_DIR/lib:$LD_LIBRARY_PATH"
export RETICULATE_PYTHON="$VENV_DIR/bin/python"

echo "=== Running ClusterLearn Demo (In-Memory Patch) ==="
cd "$PROJECT_DIR"

# Podmiana /opt/venv na ./env/venv w locie i przekazanie bezpośrednio do Rscript
sed 's|/opt/venv|./env/venv|g' clusterLearn_demo.R | Rscript -

echo "=== Execution finished ==="