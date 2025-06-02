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

# Create a non-root user and set up home directory
ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID --create-home --shell /bin/bash $USERNAME && \
    mkdir -p /home/$USERNAME/workspace && \
    chown -R $USERNAME:$USERNAME /home/$USERNAME

# Set the user
USER $USERNAME

# Set a basic working directory
WORKDIR /home/$USERNAME/workspace

# A simple entrypoint
CMD ["/bin/bash"] 