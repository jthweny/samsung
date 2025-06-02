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
# Using a known good release of Proton Clang. Replace with your specific version if needed.
# Example: Proton Clang 13.0.0-20210301 (clang-13)
ENV PROTON_CLANG_VERSION="13.0.0_20210801"
ENV PROTON_CLANG_TAR="proton-clang-${PROTON_CLANG_VERSION}.tar.gz"
# Note: Official Proton Clang releases might be on GitHub or other sources.
# This URL is a placeholder for where you'd get your specific version.
# A common source is a GitHub release from a reputable Clang build like aospa/proton-clang or kdrag0n/proton-clang.
# For this example, let's assume kdrag0n's builds (you'll need to find the exact URL for your chosen version)
# e.g., https://github.com/kdrag0n/proton-clang/releases/download/<tag>/<filename>.tar.gz
# Using a generic download example. Replace this with the actual download URL.
# For instance, from AOSP Clang prebuilts or a community build.
# The path /opt/proton-clang is a common choice.
RUN mkdir -p /opt/proton-clang && cd /opt \\
    && echo "Attempting to download Proton Clang. Replace with actual URL if this fails." \\
    # Example: This is a placeholder, find the actual URL for your desired version.
    # Using a known older kdrag0n release for demonstration as newer ones might have different structures.
    # This specific one is chosen for its known structure; replace with your actual target.
    && curl -Ls https://github.com/kdrag0n/proton-clang/releases/download/v13.0.0-20210817/proton-clang-13.0.0-20210817.tar.gz -o ${PROTON_CLANG_TAR} \\
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