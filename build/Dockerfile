FROM quay.io/operator-framework/ansible-operator:v0.13.0

# Install extra requirements
USER root

# See: https://github.com/operator-framework/operator-sdk/issues/2384
RUN pip3 install --upgrade openshift

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

# Copy ansible operator requirements
COPY watches.yaml ${HOME}/watches.yaml

COPY ansible/zuul.yaml ${HOME}/zuul.yaml
COPY ansible/group_vars/ ${HOME}/group_vars/
COPY ansible/roles/ ${HOME}/roles/

COPY build/uid_entrypoint.sh /uid_entrypoint
