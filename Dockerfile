#################### Start from the rocker/r-ver image, which always tracks the latest stable R
FROM rocker/r-ver:latest

#################### Metadata
LABEL maintainer="Szymon Nowakowski <s.nowakowski@mimuw.edu.pl>" \
      description="Custom R environment with DMRnet, xgboost, ranger, glmnet, randomForest, CatReg, DAAG, wooldridge, foreign, carData, AER, modeldata" \
      license="GPL-3" \
      org.opencontainers.image.source="https://github.com/SzymonNowakowski/statistical_machine_learning_in_r"

# Global environment variables to silence Python warnings system-wide (and for reticulate)
ENV PYTHONWARNINGS="ignore"
ENV RETICULATE_PYTHON="/opt/venv/bin/python"
ENV R_HOME="/usr/local/lib/R"
ENV LD_LIBRARY_PATH="/usr/local/lib/R/lib:${LD_LIBRARY_PATH}"

#################### System dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libgomp1 \
    libpng-dev \
    cmake \
    g++ \
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

# apply patch to 2.0.4
COPY R/predict.scope.logistic.R_patched CatReg-src/CatReg/R/predict.scope.logistic.R   

RUN R CMD build CatReg-src/CatReg \
    && R CMD INSTALL CatReg_2.0.4.tar.gz \
    && rm -rf CatReg-src CatReg_2.0.4.tar.gz

#################### Install ClusterLearn and its Python environment
# Install Python, virtual environment support and git
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    git \
    libeigen3-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure R-level startup variables (Rprofile and Renviron) to force clean environment
RUN echo "RETICULATE_PYTHON='/opt/venv/bin/python'" >> /usr/local/lib/R/etc/Renviron.site \
    && echo "PYTHONWARNINGS='ignore'" >> /usr/local/lib/R/etc/Renviron.site

# Install reticulate
RUN R -e "install.packages('reticulate', repos='https://cloud.r-project.org')"

# Create Python virtual environment
RUN python3 -m venv /opt/venv

# Install ClusterLearn dependencies
RUN /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install \
        numpy \
        pandas \
        scikit-learn \
        gurobipy

# Install and build ClusterLearn
RUN git clone https://github.com/mazumder-lab/ClusterLearn.git /opt/ClusterLearn \
    && cd /opt/ClusterLearn/univariate \
    && g++ -I/usr/include/eigen3 -fPIC -std=c++17 -c interface.cpp SegSolverCore.cpp PWQclass.cpp \ 
    && g++ -shared -Wl,-o proximal_c.so interface.o SegSolverCore.o PWQclass.o

# Add ClusterLearn directory to PYTHONPATH so Python can locate 'utils' and 'MIPSolver'
ENV PYTHONPATH="${PYTHONPATH}:/opt/ClusterLearn"

# Install missing system header libraries required to compile rpy2's C extensions
RUN apt-get update && apt-get install -y \
    libpcre2-dev \
    libdeflate-dev \
    libzstd-dev \
    liblzma-dev \
    libbz2-dev \
    zlib1g-dev \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*

# Install rpy2 in the virtual environment
RUN /opt/venv/bin/pip install rpy2

#################### Default command: just drop into shell, Rscript call must be explicit
CMD ["/bin/bash"]
