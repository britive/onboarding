FROM ubuntu:latest AS guacserver

ENV LD_LIBRARY_PATH=/usr/local/lib

RUN apt update && apt install -y make libcairo2-dev libjpeg-turbo8-dev libpng-dev libtool-bin libossp-uuid-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev wget ffmpeg

WORKDIR /opt

RUN wget -O guacamole-server-1.5.5.tar.gz "https://apache.org/dyn/closer.lua/guacamole/1.5.5/source/guacamole-server-1.5.5.tar.gz?action=download"
RUN tar -xzf guacamole-server-1.5.5.tar.gz

WORKDIR /opt/guacamole-server-1.5.5

RUN ./configure
RUN make
RUN make install

FROM ubuntu:latest

ARG USERNAME=guacamole
ARG USER_UID=1001
ARG USER_GID=$USER_UID

RUN apt update && \
    apt install -y wget unzip libcairo2-dev libossp-uuid-dev libwebp-dev ffmpeg

COPY --from=guacserver /usr/local/bin/guacenc /usr/local/bin/guacenc
COPY --from=guacserver /usr/local/lib/lib* /usr/local/lib/

ENV LD_LIBRARY_PATH=/usr/local/lib

WORKDIR /opt/

RUN wget -O awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" && \
    unzip awscliv2.zip && \
    ./aws/install

RUN rm -f awscliv2.zip

COPY ./guacsync.sh /usr/bin/guacsync

RUN chmod +x /usr/bin/guacsync

RUN useradd -m $USERNAME

WORKDIR /home/$USERNAME

USER $USERNAME

CMD ["/usr/bin/guacsync"]