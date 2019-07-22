ARG JSONNET_VERSION=0.13.0

# Jsonnet
FROM buildpack-deps:curl AS jsonnet-builder

RUN apt-get update -yq \
    && apt-get install -y make g++ \
    && curl -sL https://github.com/google/jsonnet/archive/v0.13.0.tar.gz -o jsonnet.tar.gz \
    && tar xzf jsonnet.tar.gz \
    && cd jsonnet-0.13.0 \
    && make

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl

# Kubernetes controller
FROM debian:stable
WORKDIR /opt/controller

RUN apt-get update -yq \
    && apt-get install -y jq

COPY --from=jsonnet-builder /jsonnet-0.13.0/jsonnet /usr/local/bin/jsonnet
COPY --from=jsonnet-builder /kubectl /usr/local/bin/kubectl
COPY functions.sh controller.sh ./


ENTRYPOINT ["./controller.sh"]