# nwnsc compiler
FROM jakkn/nwnsc as nwnsc
# nim image
FROM nimlang/choosenim:latest as nashor
COPY --from=nwnsc usr/local/bin/nwnsc usr/local/bin/nwnsc
COPY --from=nwnsc /nwn /nwn
RUN apt update \
    && apt upgrade -y \
    && choosenim update stable \
    && nimble install nasher -y
RUN nasher config --userName:"nasher"  
ENV PATH="/root/.nimble/bin:${PATH}"
WORKDIR /nasher
ENTRYPOINT [ "nasher" ]
CMD [ "list --quiet" ]