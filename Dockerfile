ARG JSONNET_VERSION=0.13.0

# Jsonnet
FROM buildpack-deps:curl AS jsonnet-builder

RUN apt-get update \
    && apt-get install make g++ \
    && curl -sL https://github.com/google/jsonnet/archive/v${JSONNET_VERSION}.tar.gz -o jsonnet.tar.gz \
    && tar xzf jsonnet.tar.gz \
    && cd jsonnet-${JSONNET_VERSION} \
    && make

# Kubernetes controller
FROM debian:stable
WORKDIR /opt/controller

RUN apt-get update -yq \
    && apt-get install jq \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl

COPY --from=jsonnet-builder /jsonnet-${JSONNET_VERSION}/jsonnet /usr/local/bin/jsonnet
COPY controller.sh .

ENTRYPOINT ["./controller.sh"]