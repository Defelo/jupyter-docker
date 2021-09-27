FROM jupyter/tensorflow-notebook

USER root

# update system and install dependencies
RUN set -x \
    && apt update \
    && apt dist-upgrade -y \
    && apt install -y pkg-config

# install python2 kernel
RUN set -x \
    && cd /tmp \
    && wget https://bootstrap.pypa.io/pip/2.7/get-pip.py \
    && python2 get-pip.py \
    && python2 -m pip install --upgrade ipykernel \
    && python2 -m ipykernel install


# install c++ kernel
RUN conda install -y -c conda-forge bash jupyter jupyter_contrib_nbextensions
RUN conda install -y -c conda-forge xeus-cling xtensor


# install javascript kernel
RUN set -x \
    && apt install -y nodejs npm libzmq3-dev \
    && npm install -g --unsafe-perm ijavascript \
    && ijsinstall --install=global

RUN set -x \
    && chown -R $NB_USER /home/$NB_USER \
    && rm -rf /home/$NB_USER/.local/share/jupyter

# install java jre for h2o
RUN apt install -y openjdk-8-jre


################################### Haskell ###################################

# The global snapshot package database will be here in the STACK_ROOT.
ENV STACK_ROOT=/opt/stack
RUN mkdir -p $STACK_ROOT
RUN fix-permissions $STACK_ROOT

# Install system dependencies
RUN apt install -y \
    python3-pip \
    git \
    libtinfo-dev \
    libzmq3-dev \
    libcairo2-dev \
    libpango1.0-dev \
    libmagic-dev \
    libblas-dev \
    liblapack-dev \
    libffi-dev \
    libgmp-dev \
    gnupg \
    netbase \
# for ihaskell-graphviz
    graphviz \
# for Stack download
    curl \
# Stack Debian/Ubuntu manual install dependencies
# https://docs.haskellstack.org/en/stable/install_and_upgrade/#linux-generic
    g++ \
    gcc \
    libc6-dev \
    libffi-dev \
    libgmp-dev \
    make \
    xz-utils \
    zlib1g-dev \
    git \
    gnupg \
    netbase \
# Need less for general maintenance
    less


RUN set -x \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*


# Stack Linux (generic) Manual download
# https://docs.haskellstack.org/en/stable/install_and_upgrade/#linux-generic
#
# So that we can control Stack version, we do manual install instead of
# automatic install:
#
#    curl -sSL https://get.haskellstack.org/ | sh
#
ARG STACK_VERSION="2.5.1"
ARG STACK_BINDIST="stack-${STACK_VERSION}-linux-x86_64"
RUN set -x \
    && cd /tmp \
    && curl -sSL --output ${STACK_BINDIST}.tar.gz https://github.com/commercialhaskell/stack/releases/download/v${STACK_VERSION}/${STACK_BINDIST}.tar.gz \
    && tar zxf ${STACK_BINDIST}.tar.gz \
    && cp ${STACK_BINDIST}/stack /usr/bin/stack \
    && rm -rf ${STACK_BINDIST}.tar.gz ${STACK_BINDIST} \
    && stack --version

# Stack global non-project-specific config stack.config.yaml
# https://docs.haskellstack.org/en/stable/yaml_configuration/#non-project-specific-config
RUN mkdir -p /etc/stack
COPY stack.config.yaml /etc/stack/config.yaml
RUN fix-permissions /etc/stack

# Stack global project stack.yaml
# https://docs.haskellstack.org/en/stable/yaml_configuration/#yaml-configuration
RUN mkdir -p $STACK_ROOT/global-project
COPY global-project.stack.yaml $STACK_ROOT/global-project/stack.yaml
RUN set -x \
    && chown --recursive $NB_UID:users $STACK_ROOT/global-project \
    && fix-permissions $STACK_ROOT/global-project

# fix-permissions for /usr/local/share/jupyter so that we can install
# the IHaskell kernel there. Seems like the best place to install it, see
#      jupyter --paths
#      jupyter kernelspec list
RUN set -x \
    && mkdir -p /usr/local/share/jupyter \
    && fix-permissions /usr/local/share/jupyter \
    && mkdir -p /usr/local/share/jupyter/kernels \
    && fix-permissions /usr/local/share/jupyter/kernels

# Now make a bin directory for installing the ihaskell executable on
# the PATH. This /opt/bin is referenced by the stack non-project-specific
# config.
RUN set -x \
    && mkdir -p /opt/bin \
    && fix-permissions /opt/bin
ENV PATH ${PATH}:/opt/bin

# Specify a git branch for IHaskell (can be branch or tag).
# The resolver for all stack builds will be chosen from
# the IHaskell/stack.yaml in this commit.
# https://github.com/gibiansky/IHaskell/commits/master
# IHaskell 2020-11-23
ARG IHASKELL_COMMIT=5b7e03b2caad17a51cb7490d66bf808e0e8b9d4a
# Specify a git branch for hvega
# https://github.com/DougBurke/hvega/commits/master
# hvega 2020-11-09
ARG HVEGA_COMMIT=77168ddd15a50a6db6d44f76232eebe7c2b507b7

# Clone IHaskell and install ghc from the IHaskell resolver
RUN set -x \
    && cd /opt \
    && curl -L "https://github.com/gibiansky/IHaskell/tarball/$IHASKELL_COMMIT" | tar xzf - \
    && mv *IHaskell* IHaskell \
    && curl -L "https://github.com/DougBurke/hvega/tarball/$HVEGA_COMMIT" | tar xzf - \
    && mv *hvega* hvega \
# Copy the Stack global project resolver from the IHaskell resolver.
    && grep 'resolver:' /opt/IHaskell/stack.yaml >> $STACK_ROOT/global-project/stack.yaml \
    && fix-permissions /opt/IHaskell \
    && fix-permissions $STACK_ROOT \
    && fix-permissions /opt/hvega \
    && stack setup \
    && fix-permissions $STACK_ROOT \
# Clean 176MB
    && rm /opt/stack/programs/x86_64-linux/ghc*.tar.xz

# ghc-parser and ipython-kernel are dependencies of ihaskell.
# Build them first in separate RUN commands so we don't exceed Dockerhub
# resource limits and fail with no build log.
#
# Also --jobs 1 to prevent the build from running out of memory on Dockerhub.
# (ghc: internal error: Unable to commit 1048576 bytes of memory)
#
# https://success.docker.com/article/docker-hub-automated-build-fails-and-the-logs-are-missing-empty
#
# Build ghc-parser
RUN set -x \
    && stack --jobs 1 build $STACK_ARGS ghc-parser \
    && fix-permissions /opt/IHaskell \
    && fix-permissions $STACK_ROOT
# Build ipython-kernel
RUN set -x \
    && stack --jobs 1 build $STACK_ARGS ipython-kernel \
    && fix-permissions /opt/IHaskell \
    && fix-permissions $STACK_ROOT
# Build IHaskell
RUN set -x \
    && stack --jobs 1 build $STACK_ARGS ihaskell \
# Note that we are NOT in the /opt/IHaskell directory here, we are
# installing ihaskell via the paths given in /opt/stack/global-project/stack.yaml
    && fix-permissions /opt/IHaskell \
    && fix-permissions $STACK_ROOT

# Install IHaskell.Display libraries
# https://github.com/gibiansky/IHaskell/tree/master/ihaskell-display
RUN set -x \
    && stack build $STACK_ARGS ihaskell-aeson \
    && stack build $STACK_ARGS ihaskell-blaze \
    && stack build $STACK_ARGS ihaskell-charts \
    && stack build $STACK_ARGS ihaskell-diagrams \
    && stack build $STACK_ARGS ihaskell-gnuplot \
    && stack build $STACK_ARGS ihaskell-graphviz \
    && stack build $STACK_ARGS ihaskell-hatex \
    && stack build $STACK_ARGS ihaskell-juicypixels \
#   && stack build $STACK_ARGS ihaskell-magic \
#   && stack build $STACK_ARGS ihaskell-plot \
#   && stack build $STACK_ARGS ihaskell-rlangqq \
#   && stack build $STACK_ARGS ihaskell-static-canvas \
# Skip install of ihaskell-widgets, they don't work.
# See https://github.com/gibiansky/IHaskell/issues/870
#   && stack build $STACK_ARGS ihaskell-widgets \
    && stack build $STACK_ARGS hvega \
    && stack build $STACK_ARGS ihaskell-hvega \
    && fix-permissions $STACK_ROOT \
# Fix for https://github.com/jamesdbrock/ihaskell-notebook/issues/14#issuecomment-636334824
    && fix-permissions /opt/IHaskell \
    && fix-permissions /opt/hvega

# Cleanup
# Don't clean IHaskell/.stack-work, 7GB, this causes issue #5
#   && rm -rf $(find /opt/IHaskell -type d -name .stack-work) \
# Don't clean /opt/hvega
# We can't actually figure out anything to cleanup.

# Bug workaround for https://github.com/jamesdbrock/ihaskell-notebook/issues/9
RUN set -x \
    && mkdir -p /home/jovyan/.local/share/jupyter/runtime \
    && fix-permissions /home/jovyan/.local \
    && fix-permissions /home/jovyan/.local/share \
    && fix-permissions /home/jovyan/.local/share/jupyter \
    && fix-permissions /home/jovyan/.local/share/jupyter/runtime

# Install system-level ghc using the ghc which was installed by stack
# using the IHaskell resolver.
RUN set -x \
    && mkdir -p /opt/ghc && ln -s `stack path --compiler-bin` /opt/ghc/bin \
    && fix-permissions /opt/ghc
ENV PATH ${PATH}:/opt/ghc/bin


# Reset user from jupyter/base-notebook
USER $NB_USER


RUN set -x \
# Install the IHaskell kernel at /usr/local/share/jupyter/kernels, which is
# in `jupyter --paths` data:
    && stack exec ihaskell -- install --stack --prefix=/usr/local \
# Add the --codemirror Haskell switch to enable syntax highlighting
    && sed --in-place s/"\+RTS"/--codemirror\",\"Haskell\",\"+RTS/ /usr/local/share/jupyter/kernels/haskell/kernel.json
# " This line is just to close the double-quote for syntax highlighting in the Dockerfile


# install bash kernel
RUN /opt/conda/bin/pip install --no-cache-dir bash_kernel
RUN /opt/conda/bin/python -m bash_kernel.install


# install h2o
RUN /opt/conda/bin/pip install --no-cache-dir --upgrade h2o && \
    /opt/conda/bin/pip install --no-cache-dir --upgrade pandas
