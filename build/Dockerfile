FROM quay.io/operator-framework/ansible-operator:v0.13.0

# Install extra requirements
USER root

# See: https://github.com/operator-framework/operator-sdk/issues/2384
# Install gear to connect to the scheduler gearman
RUN pip3 install --upgrade openshift gear

# unarchive: bzip2 and tar
# generate zuul ssh-keys or certificate: openssh and openssl
# manage configuration: git
RUN dnf install -y bzip2 tar openssh openssl git

# Install dhall-to-json
RUN curl -OL https://github.com/dhall-lang/dhall-haskell/releases/download/1.29.0/dhall-json-1.6.1-x86_64-linux.tar.bz2            \
  && echo "7e65f933fb215629d18d23bc774688c598d4c11b62865f3546ee23ae36b25290  dhall-json-1.6.1-x86_64-linux.tar.bz2" | sha256sum -c \
  && tar -xf dhall-json-1.6.1-x86_64-linux.tar.bz2 --strip-components=2 -j --mode='a+x' -C /usr/bin                                \
  && rm dhall-json-1.6.1-x86_64-linux.tar.bz2

# Back to the default operator user
USER 1001

# Install dhall libraries
RUN git clone --branch v13.0.0 --depth 1 https://github.com/dhall-lang/dhall-lang       /opt/ansible/dhall-lang                    \
  && git clone --branch v3.0.0 --depth 1 https://github.com/dhall-lang/dhall-kubernetes /opt/ansible/dhall-kubernetes
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
