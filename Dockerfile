ARG KIELE_COMMIT
FROM runtimeverificationinc/runtimeverification-iele-semantics:ubuntu-focal-${KIELE_COMMIT}

RUN    apt update        \
    && apt upgrade --yes \
    && apt install --yes \
       make              \
       g++-8             \
       curl              \
       tar               \
       libboost-all-dev  \
       llvm-10           \
       llvm-10-dev       \
       libz3-dev         \
       libxml2-utils     \
       gcovr

RUN curl -s "https://cmake.org/files/v3.16/cmake-3.16.3-Linux-x86_64.tar.gz" | \
    tar --strip-components=1 -xz -C /usr/local

ARG USER_ID=1000
ARG GROUP_ID=1000
RUN    groupadd --gid $GROUP_ID user \
    && useradd --create-home --uid $USER_ID --shell /bin/sh --gid user user

USER $USER_ID:$GROUP_ID
