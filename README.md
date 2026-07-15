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
  -t szymonnowakowski/statistical_machine_learning_in_r:latest \
  -t szymonnowakowski/statistical_machine_learning_in_r:r4.6.1-20260714 \
  .

docker push szymonnowakowski/statistical_machine_learning_in_r:latest
docker push szymonnowakowski/statistical_machine_learning_in_r:r4.6.1-20260714
```

## Test run
```
docker run --rm \
    -v "$PWD:/work" \
    -w /work \
    statistical_machine_learning_in_r:latest \
    Rscript clusterlearn_demo.R
```
