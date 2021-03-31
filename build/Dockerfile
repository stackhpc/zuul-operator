FROM quay.io/operator-framework/ansible-operator:v1.4.2

# dhall versions and digests
ARG DHALL_VERSION=1.33.1
ARG DHALL_JSON_VERSION=1.7.0
ARG DHALL_JSON_DIGEST=cc9fc70e492d35a3986183b589a435653e782f67cda51d33a935dff1ddd15aec
ARG DHALL_LANG_REF=v17.0.0
ARG DHALL_KUBE_REF=v4.0.0

# kubectl versions and digests
ARG KUBECTL_VERSION=v1.17.0
ARG KUBECTL_DIGEST=a5eb7e2e44d858d96410937a4e4c82f9087c9d120cb2b9e92462878eda59d578

# Install extra requirements
USER root

# Install gear to connect to the scheduler gearman
RUN pip3 install --upgrade gear

# Install collections
RUN ansible-galaxy collection install community.kubernetes && chmod -R ug+rwx ${HOME}/.ansible

# unarchive: bzip2 and tar
# generate zuul ssh-keys or certificate: openssh and openssl
# manage configuration: git
RUN dnf install -y bzip2 tar openssh openssl git

# Install kubectl to mitigate https://github.com/operator-framework/operator-sdk/issues/2204
RUN curl -OL https://dl.k8s.io/$KUBECTL_VERSION/kubernetes-client-linux-amd64.tar.gz                                                          \
  && echo "$KUBECTL_DIGEST  kubernetes-client-linux-amd64.tar.gz" | sha256sum -c                                                              \
  && tar -xf kubernetes-client-linux-amd64.tar.gz --strip-components=3 -z --mode='a+x' -C /usr/bin                                            \
  && rm kubernetes-client-linux-amd64.tar.gz

# Install dhall-to-json
RUN curl -OL https://github.com/dhall-lang/dhall-haskell/releases/download/$DHALL_VERSION/dhall-json-$DHALL_JSON_VERSION-x86_64-linux.tar.bz2 \
  && echo "$DHALL_JSON_DIGEST  dhall-json-$DHALL_JSON_VERSION-x86_64-linux.tar.bz2" | sha256sum -c                                            \
  && tar -xf dhall-json-$DHALL_JSON_VERSION-x86_64-linux.tar.bz2 --strip-components=2 -j --mode='a+x' -C /usr/bin                             \
  && rm dhall-json-$DHALL_JSON_VERSION-x86_64-linux.tar.bz2

# Back to the default operator user
USER 1001

# Install dhall libraries
RUN git clone  --branch $DHALL_LANG_REF --depth 1 https://github.com/dhall-lang/dhall-lang       /opt/ansible/dhall-lang                      \
  && git clone --branch $DHALL_KUBE_REF --depth 1 https://github.com/dhall-lang/dhall-kubernetes /opt/ansible/dhall-kubernetes
ENV DHALL_PRELUDE=/opt/ansible/dhall-lang/Prelude/package.dhall
ENV DHALL_KUBERNETES=/opt/ansible/dhall-kubernetes/package.dhall

# Copy configuration
COPY conf/ /opt/ansible/conf/

# Cache dhall objects
RUN echo 'let Prelude = ~/conf/Prelude.dhall let Kubernetes = ~/conf/Kubernetes.dhall in "OK"' | \
    env DHALL_PRELUDE=/opt/ansible/dhall-lang/Prelude/package.dhall                              \
        DHALL_KUBERNETES=/opt/ansible/dhall-kubernetes/package.dhall dhall-to-json

# Copy ansible operator requirements
COPY watches.yaml ${HOME}/watches.yaml
COPY roles ${HOME}/roles
