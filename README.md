# statistical_machine_learning_in_r
R ML environment with glmnet, xgboost, ranger, DMRnet, CatReg, RandomForest, grpreg etc. + supp. datasets


## Check the newest R version available
```{bash}
docker run --rm rocker/r-ver:latest R --version
```

Say it is `4.6.1`

## Build, tag and upload the docker image
```{bash}
docker build \
  -t snowakowski/statistical_machine_learning_in_r:latest \
  -t snowakowski/statistical_machine_learning_in_r:r4.6.1-20260717 \
  .

docker push snowakowski/statistical_machine_learning_in_r:latest
docker push snowakowski/statistical_machine_learning_in_r:r4.6.1-20260717
```

## Test run

### Run the demo script
```
docker run --rm \
    -v "$PWD:/work" \
    -w /work \
    snowakowski/statistical_machine_learning_in_r:latest \
    Rscript clusterLearn_demo.R
```

#### Run the demo script with exact solution

In addition to the previous demo script, the exact demo uses Gurobi engine. 
Accordingly, we need to pass the current directory (where the licence is located) as the `/opt/gurobi` directory because that is where the Gurobi license file is expected to be found. The Gurobi license file is not included in the docker image for licensing reasons.
Make sure to have the Gurobi license file in the current directory before running the following command.

```
docker run --rm \
    -v "$PWD:/work" \
    -v "$PWD:/opt/gurobi" \
    -w /work \
    snowakowski/statistical_machine_learning_in_r:latest \
    Rscript clusterLearn_demo_exact.R
```