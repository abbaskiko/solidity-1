ARG KIELE_COMMIT
FROM runtimeverificationinc/runtimeverification-iele-semantics:ubuntu-bionic-${KIELE_COMMIT}

RUN    apt update        \
    && apt upgrade --yes \
    && apt install --yes \
       build-essential   \
       cmake             \
       libxml2-utils     \
       gcovr

ARG USER_ID=1000
ARG GROUP_ID=1000
RUN    groupadd --gid $GROUP_ID user \
    && useradd --create-home --uid $USER_ID --shell /bin/sh --gid user user

USER $USER_ID:$GROUP_ID
