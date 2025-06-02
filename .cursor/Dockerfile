FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Basic tools and network test
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    iputils-ping \
    dnsutils \
    && echo "INFO: Testing network connectivity..." && \
    ping -c 1 8.8.8.8 && \
    nslookup github.com && \
    echo "INFO: Network test complete." && \
    echo "INFO: Installing additional build packages..." && \
    apt-get install -y --no-install-recommends \
    git \
    python3-pip \
    bc \
    cpio \
    kmod \
    imagemagick \
    libncurses5-dev \
    libssl-dev \
    build-essential \
    zip \
    curl \
    libncurses-dev \
    flex \
    bison \
    libelf-dev \
    device-tree-compiler \
    rsync \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set a basic working directory
WORKDIR /home/user/workspace

# A simple entrypoint
CMD ["/bin/bash"] 