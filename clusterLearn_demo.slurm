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

# Export R paths required by rpy2 at runtime
export R_HOME=$(R RHOME)
export LD_LIBRARY_PATH="$R_HOME/lib:$LD_LIBRARY_PATH"

# Activate Python virtual environment
source "$VENV_DIR/bin/activate"

echo "=== Running ClusterLearn Demo ==="
cd "$PROJECT_DIR"
Rscript clusterLearn_demo.R

echo "=== Execution finished ==="