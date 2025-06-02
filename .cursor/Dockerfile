FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Basic tools and network test
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    git \
    iputils-ping \
    dnsutils \
    python3-pip \
    && echo "INFO: Testing network connectivity..." && \
    ping -c 1 8.8.8.8 && \
    nslookup github.com && \
    echo "INFO: Network test complete." && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set a basic working directory
WORKDIR /home/user/workspace

# A simple entrypoint
CMD ["/bin/bash"] 