# install docker

curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun

curl -fsSL https://get.docker.com | bash -s docker
sudo gpasswd -a haswell docker
newgrp docker

echo `{
  "data-root": "/mydata/docker"
}` > /etc/docker/daemon.json

sudo systemctl restart docker

# mount /opt
#
# --------------------------------------------------
# TODO: change it
# set DIR 
BUILDER_WORK_DIR="/mydata/torch/v110"
PYTORCH_TAG="v1.10.2"
PYTORCH_BUILD_VERSION="1.10.2"
# BUILDER_WORK_DIR="/opt/tt"
# PYTORCH_TAG="v1.12.2"
# BUILDER_TAG="release/1.12"
BUILDER_TAG="release/1.10"
GPU_ARCH_VERSION=11.3
GPU_ARCH_TYPE=cuda
# TODO: change ABOVE
# --------------------------------------------------

# 注意权限
sudo mkdir -p $BUILDER_WORK_DIR
# sudo chown haswell:docker $BUILDER_WORK_DIR
cd $BUILDER_WORK_DIR
# 注意权限

git clone https://github.com/pytorch/builder
cd builder
git checkout $BUILDER_TAG
git submodule update --init --recursive
# 要手动改builder/manywheel/build_cuda.sh USE_STATIC_NCCL=0
# sed -i '/USE_STATIC_NCCL/s/1/0/g' manywheel/build_cuda.sh 
sed -i '/USE_STATIC_NCCL/s/1/0/g' manywheel/build.sh 
# 要手动改builder/manywheel/build_cuda.sh USE_STATIC_NCCL=0
GPU_ARCH_TYPE=$GPU_ARCH_TYPE GPU_ARCH_VERSION=$GPU_ARCH_VERSION manywheel/build_docker.sh
cd ..



git clone https://github.com/pytorch/pytorch
cd pytorch
CIRCLE_SHA1=$((git rev-parse HEAD))
git submodule update --init --recursive
git rev-parse HEAD
# python setup.py clean # builder会清理
cd ..

# only for ubuntu
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb
sudo dpkg -i cuda-keyring_1.0-1_all.deb
sudo apt-get update
sudo apt install libnccl2=2.14.3-1+cuda11.0 libnccl-dev=2.14.3-1+cuda11.0

mkdir -p "$BUILDER_WORK_DIR/nccl"
mkdir -p "$BUILDER_WORK_DIR/nccl/lib"
mkdir -p "$BUILDER_WORK_DIR/nccl/include"
cp /usr/lib/x86_64-linux-gnu/libnccl* "$BUILDER_WORK_DIR/nccl/lib"
cp /usr/include/nccl* "$BUILDER_WORK_DIR/nccl/include"

# NCCL CONFIG
# TODO: need change
GITHUB_WORKSPACE="$BUILDER_WORK_DIR"
RUNNER_TEMP="$BUILDER_WORK_DIR"
PYTORCH_ROOT=/pytorch
PYTORCH_FINAL_PACKAGE_DIR=/artifacts
ANACONDA_USER=pytorch
BINARY_ENV_FILE=/tmp/env
if [[ $PYTORCH_TAG == "v1.10.2" ]]; then
  BINARY_ENV_FILE=//env
fi
# DOCKER_IMAGE=pytorch/manylinux-builder:cuda11.3-1.10
# DOCKER_IMAGE=pytorch/manylinux-cuda113:latest
DOCKER_IMAGE=pytorch/manylinux-builder:cuda11.3

# GEN NCCL CONFIG
NCCL_GLOBAL_DIR="/weka-jd/prod/platform_team/zly/lib/nccl/2.14.3_cu113"
NCCL_ENV_FILE="${NCCL_GLOBAL_DIR}/nccl_env.sh"
NCCL_ENV_FILE_HOSTPATH="${GITHUB_WORKSPACE}/nccl/nccl_env.sh"
echo "export NCCL_INCLUDE_DIR=${NCCL_GLOBAL_DIR}/include" > ${NCCL_ENV_FILE_HOSTPATH}
echo "export NCCL_LIB_DIR=${NCCL_GLOBAL_DIR}/lib" >> ${NCCL_ENV_FILE_HOSTPATH}
echo "export NCCL_ROOT_DIR=${NCCL_GLOBAL_DIR}" >> ${NCCL_ENV_FILE_HOSTPATH}
# 要手动改builder/manywheel/build_cuda.sh USE_STATIC_NCCL=0
# 要手动改builder/manywheel/build_cuda.sh USE_STATIC_NCCL=0
# 要手动改builder/manywheel/build_cuda.sh NCCL_ROOT_DIR=
# 要手动改builder/manywheel/build_cuda.sh NCCL_ROOT_DIR=0
echo "export USE_STATIC_NCCL=0" >> ${NCCL_ENV_FILE_HOSTPATH}
echo "export USE_SYSTEM_NCCL=1" >> ${NCCL_ENV_FILE_HOSTPATH}

#GEN ENV file
DOCKER_ENV_FILENAME="my_env.env"
cat >"$DOCKER_ENV_FILENAME" <<EOL
GITHUB_WORKSPACE=$GITHUB_WORKSPACE
RUNNER_TEMP=$RUNNER_TEMP

ANACONDA_USER=$ANACONDA_USER
BINARY_ENV_FILE=$BINARY_ENV_FILE
BUILD_ENVIRONMENT=manywheel 3.8 cu113
BUILDER_ROOT=/builder
IS_GHA=1
PYTORCH_FINAL_PACKAGE_DIR=$PYTORCH_FINAL_PACKAGE_DIR
PYTORCH_ROOT=$PYTORCH_ROOT
SKIP_ALL_TESTS=1
# TODO: This is a legacy variable that we eventually want to get rid of in
#       favor of GPU_ARCH_VERSION
PACKAGE_TYPE=manywheel
DESIRED_CUDA=cu113
GPU_ARCH_VERSION=$GPU_ARCH_VERSION
GPU_ARCH_TYPE=$GPU_ARCH_TYPE
DOCKER_IMAGE=$DOCKER_IMAGE
DESIRED_PYTHON=3.8
BUILD_SPLIT_CUDA='ON'
CIRCLE_SHA1=$CIRCLE_SHA1
CIRCLE_TAG=$PYTORCH_TAG
CIRCLE_BRANCH=$PYTORCH_TAG
PYTORCH_BUILD_VERSION=$PYTORCH_TAG
CIRCLE_WORKFLOW_ID='123321_321123'
EOL

# set -x
mkdir -p artifacts/
container_name=$(docker run \
    --env-file=${DOCKER_ENV_FILENAME} \
    --tty \
    --detach \
    -v "${GITHUB_WORKSPACE}/pytorch:/pytorch" \
    -v "${GITHUB_WORKSPACE}/builder:/builder" \
    -v "${RUNNER_TEMP}/artifacts:/artifacts" \
    -v "${RUNNER_TEMP}/artifacts:/final_pkgs" \
    -v "${GITHUB_WORKSPACE}/nccl:${NCCL_GLOBAL_DIR}" \
    -w / \
    "${DOCKER_IMAGE}"
)
docker exec -t -w "${PYTORCH_ROOT}" "${container_name}" bash -c "bash .circleci/scripts/binary_populate_env.sh"
docker exec -t "${container_name}" bash -c "source ${BINARY_ENV_FILE} && source ${NCCL_ENV_FILE} && bash /builder/manywheel/build.sh"
# docker exec -t "${container_name}" bash -c "bash /builder/manywheel/build.sh"
# for PYTORCH_TAG == v1.10.2
# docker exec -t "${container_name}" bash -c "source /env && source ${NCCL_ENV_FILE} && bash /builder/manywheel/build.sh"
