# nwnsc compiler
FROM nwneetools/nwnsc:latest as nwnsc
# nim image
FROM nimlang/nim:latest as nasher
COPY --from=nwnsc usr/local/bin/nwnsc usr/local/bin/nwnsc
COPY --from=nwnsc /nwn /nwn
RUN dpkg --add-architecture i386 \
    && apt update \
    && apt upgrade -y \
    && apt-get install libc6:i386 libncurses5:i386 libstdc++6:i386 -y \
    && rm -fr /var/lib/apt/lists/* /root/.cache/* /usr/share/doc/* /var/cache/man/*
ARG NASHER_VERSION="0.14.2"
RUN adduser nasher --disabled-password --gecos "" --uid 1000
RUN echo "nasher ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && usermod -aG sudo nasher
WORKDIR /nasher
RUN chown -R nasher:nasher /nwn /usr/local/bin/nwnsc /nasher
USER nasher
ENV PATH="/home/nasher/.nimble/bin:$PATH"
RUN nimble install nasher@#${NASHER_VERSION} -y
RUN chmod +x /home/nasher/.nimble/bin/nasher
RUN nasher config --nssFlags:"-n /nwn/data -o" \
    && nasher config --installDir:"/nasher/install" \
    && nasher config --userName:"nasher"
WORKDIR /nasher
RUN bash -c "mkdir -pv /nasher/install/{erf,hak,modules,tlk}"
ENTRYPOINT [ "nasher" ]
CMD [ "--help" ]
