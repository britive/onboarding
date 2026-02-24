# GuacSync - Guacamole recording conversion and S3 sync service
# Stage 1: Build guacenc from guacamole-server source
FROM ubuntu:latest AS guacserver

ENV LD_LIBRARY_PATH=/usr/local/lib

RUN apt-get update && apt-get install -y \
    make \
    libcairo2-dev \
    libjpeg-turbo8-dev \
    libpng-dev \
    libtool-bin \
    libossp-uuid-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev \
    wget \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN wget -O guacamole-server-1.5.5.tar.gz \
    "https://apache.org/dyn/closer.lua/guacamole/1.5.5/source/guacamole-server-1.5.5.tar.gz?action=download"
RUN tar -xzf guacamole-server-1.5.5.tar.gz

WORKDIR /opt/guacamole-server-1.5.5

RUN ./configure
RUN make
RUN make install

# Stage 2: Runtime image with guacenc binary and AWS CLI
FROM ubuntu:latest

ARG USERNAME=guacamole
ARG USER_UID=1001
ARG USER_GID=$USER_UID

RUN apt-get update && \
    apt-get install -y wget unzip libcairo2-dev libossp-uuid-dev libwebp-dev ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=guacserver /usr/local/bin/guacenc /usr/local/bin/guacenc
COPY --from=guacserver /usr/local/lib/lib* /usr/local/lib/

ENV LD_LIBRARY_PATH=/usr/local/lib

WORKDIR /opt/

# Install AWS CLI v2 (platform-aware)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"; \
    else \
        AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"; \
    fi && \
    wget -O awscliv2.zip "$AWS_CLI_URL" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

COPY ./guacsync.sh /usr/bin/guacsync
RUN chmod +x /usr/bin/guacsync

RUN useradd -m $USERNAME

WORKDIR /home/$USERNAME

USER $USERNAME

CMD ["/usr/bin/guacsync"]
