FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install Core Build Tools, Python, and other utilities
RUN apt-get update && apt-get install -y --no-install-recommends \\
    build-essential \\
    git \\
    bc \\
    bison \\
    flex \\
    libssl-dev \\
    libncurses-dev \\
    libelf-dev \\
    cpio \\
    rsync \\
    dos2unix \\
    shellcheck \\
    wget \\
    curl \\
    unzip \\
    p7zip-full \\
    python3 \\
    python3-pip \\
    device-tree-compiler \\
    # For aarch64-linux-gnu-gcc if Proton Clang fails or for specific host tools
    gcc-aarch64-linux-gnu \\
    g++-aarch64-linux-gnu \\
    # Add any other utilities you find necessary
    && rm -rf /var/lib/apt/lists/*

# 2. Setup User (Cursor agent often runs as a non-root user like 'user' or 'codespace')
# Using 'user' as an example. UID/GID 1000 is common.
ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \\
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \\
    && apt-get update \\
    && apt-get install -y sudo \\
    && echo $USERNAME ALL=\\(root\\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \\
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*
USER $USERNAME
WORKDIR /home/$USERNAME/workspace

# 3. Install Proton Clang
ENV PROTON_CLANG_TAG="v13.0.0-20210817"
ENV PROTON_CLANG_VERSION_NAME="proton-clang-13.0.0-20210817"
ENV PROTON_CLANG_TAR="${PROTON_CLANG_VERSION_NAME}.tar.gz"

RUN mkdir -p /opt/proton-clang && cd /opt \\
    && echo "Downloading Proton Clang ${PROTON_CLANG_TAG}..." \\
    && curl -Ls "https://github.com/kdrag0n/proton-clang/releases/download/${PROTON_CLANG_TAG}/${PROTON_CLANG_TAR}" -o ${PROTON_CLANG_TAR} \\
    && tar -xzf ${PROTON_CLANG_TAR} -C /opt/proton-clang --strip-components=1 \\
    && rm ${PROTON_CLANG_TAR}

# Ensure the toolchain is in PATH for the user
ENV PATH="/opt/proton-clang/bin:${PATH}"

# 4. Verify/Symlink DTC
# The `device-tree-compiler` package usually installs dtc to /usr/bin/dtc.
# The build script expects it at /usr/local/bin/dtc. Create a symlink.
# This needs to be done as root, so we'll handle it in environment.json's "onCreateCommand"
# or you'd use `sudo` here if the user has sudo rights without password.
# For now, we assume the onCreateCommand or a setup script will handle this:
# RUN sudo ln -sf /usr/bin/dtc /usr/local/bin/dtc

# Set user again in case any previous RUN commands switched to root
USER $USERNAME
WORKDIR /home/$USERNAME/workspace

# Default command (optional, agent will override)
CMD ["/bin/bash"] 