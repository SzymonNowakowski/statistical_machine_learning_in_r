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
  -t snowakowski/statistical_machine_learning_in_r:r4.6.1-20260716 \
  .

docker push snowakowski/statistical_machine_learning_in_r:latest
docker push snowakowski/statistical_machine_learning_in_r:r4.6.1-20260716
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

```
docker run --rm \
    -v "$PWD:/work" \
    -w /work \
    snowakowski/statistical_machine_learning_in_r:latest \
    Rscript clusterLearn_demo_exact.R
```