#################### Start from the rocker/r-ver image
FROM rocker/r-ver:latest

#################### Metadata
LABEL maintainer="Szymon Nowakowski <s.nowakowski@mimuw.edu.pl>" \
      description="Custom R environment with DMRnet, xgboost, ranger, glmnet, randomForest, CatReg, DAAG, wooldridge, foreign, carData, AER, modeldata, and ClusterLearn C++ wrapper" \
      license="GPL-3" \
      org.opencontainers.image.source="https://github.com/SzymonNowakowski/statistical_machine_learning_in_r"

#################### System dependencies (added git and libeigen3-dev for ClusterLearn)
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libgomp1 \
    libpng-dev \
    cmake \
    g++ \
    git \
    libeigen3-dev \
    && rm -rf /var/lib/apt/lists/*

#################### Install selected R packages - layered build
RUN R -e "install.packages('xgboost', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('glmnet', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('ranger', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('grpreg', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('DMRnet', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('randomForest', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('digest', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('DAAG', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('wooldridge', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('foreign', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('carData', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('AER', repos='https://cloud.r-project.org')"
RUN R -e "install.packages('modeldata', repos='https://cloud.r-project.org')"

#################### Install CatReg from patched source tarball
RUN apt-get update && apt-get install -y wget tar && rm -rf /var/lib/apt/lists/* \
    && wget -O CatReg_2.0.4.tar.gz https://cran.r-project.org/src/contrib/CatReg_2.0.4.tar.gz \
    && mkdir CatReg-src \
    && tar -xzf CatReg_2.0.4.tar.gz -C CatReg-src

# Apply patch to CatReg 2.0.4
COPY R/predict.scope.logistic.R_patched CatReg-src/CatReg/R/predict.scope.logistic.R   

RUN R CMD build CatReg-src/CatReg \
    && R CMD INSTALL CatReg_2.0.4.tar.gz \
    && rm -rf CatReg-src CatReg_2.0.4.tar.gz

#################### Compile ClusterLearn C++ Shared Library
# Komenda git clone automatycznie stworzy katalog /opt/ClusterLearn
RUN git clone https://github.com/mazumder-lab/ClusterLearn.git /opt/ClusterLearn \
    && cd /opt/ClusterLearn/univariate \
    && g++ -I/usr/include/eigen3 -fPIC -std=c++17 -c interface.cpp SegSolverCore.cpp PWQclass.cpp \ 
    && g++ -shared -Wl,-o BCD_solver.so interface.o SegSolverCore.o PWQclass.o

#################### Setup ClusterLearn Wrapper in R Startup Profile
# Tworzymy dedykowany katalog i kopiujemy plik wrapper-a bezpośrednio do kontenera
RUN mkdir -p /opt/R
COPY R/BCD_wrapper.R /opt/R/BCD_wrapper.R

# Informujemy profil startowy R, by ładował ten skrypt przy każdym uruchomieniu
RUN echo "source('/opt/R/BCD_wrapper.R')" >> /usr/local/lib/R/etc/Rprofile.site

#################### Default command: Launch R interactive terminal by default
CMD ["R"]
