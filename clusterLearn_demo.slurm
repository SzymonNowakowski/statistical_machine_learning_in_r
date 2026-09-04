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
module load python/3.9.1

echo "=== Setting up environment ==="
PROJECT_DIR=$(pwd)
VENV_DIR="$PROJECT_DIR/env/venv"

export R_HOME=$(R RHOME)
export LD_LIBRARY_PATH="$R_HOME/lib:$LD_LIBRARY_PATH"

source "$VENV_DIR/bin/activate"
export RETICULATE_PYTHON="$VENV_DIR/bin/python"

echo "=== Running ClusterLearn Demo (In-Memory Patch) ==="
cd "$PROJECT_DIR"

# Run the R script with in-memory patching to replace /opt/venv with ./env/venv
sed 's|/opt/venv|./env/venv|g' clusterLearn_demo.R | Rscript -

echo "=== Execution finished ==="