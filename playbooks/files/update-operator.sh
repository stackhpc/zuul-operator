#!/bin/bash -e
# Update the operator image
echo "Remove previous operator"
kubectl delete -f deploy/operator.yaml || :

BUILDAH_OPTS=${BUILDAH_OPTS:-}
if test -d /var/lib/silverkube/storage; then
    BUILDAH_OPTS="${BUILDAH_OPTS} --root /var/lib/silverkube/storage --storage-driver vfs"
fi

echo "Update local image"
CTX=$(sudo buildah from  --pull-never ${BUILDAH_OPTS} docker.io/zuul/zuul-operator:latest)
MNT=$(sudo buildah mount ${BUILDAH_OPTS} $CTX)

sudo rsync -avi --delete roles/ ${MNT}/opt/ansible/roles/
sudo rsync -avi --delete conf/ ${MNT}/opt/ansible/conf/

sudo buildah commit ${BUILDAH_OPTS} --rm ${CTX} docker.io/zuul/zuul-operator:latest

kubectl apply -f deploy/operator.yaml
