# LineageOS 20 编译环境（Ubuntu 20.04 + 全依赖）
# Fedora 宿主上用 podman/docker 构建并运行本镜像。
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      git git-lfs curl wget rsync ccache \
      flex bison gperf build-essential zip unzip bc \
      python3 python2.7 python-is-python2 \
      libncurses5 libtinfo5 libssl-dev \
      libxml2 libxml2-utils xsltproc zlib1g-dev \
      lib32z1-dev libc6-dev-i386 lib32stdc++6 gcc-multilib g++-multilib \
      imagemagick pngcrush schedtool squashfs-tools lzop liblz4-tool lz4 \
      openjdk-11-jdk-headless \
      android-sdk-libsparse-utils \
 && rm -rf /var/lib/apt/lists/*

# repo 工具
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
 && chmod a+x /usr/local/bin/repo

# 容器内 git 默认身份（不影响宿主的源码归属）
RUN git config --system user.name  "los-builder" \
 && git config --system user.email "los-builder@local" \
 && git config --system color.ui   false

WORKDIR /lineage
CMD ["/bin/bash"]
