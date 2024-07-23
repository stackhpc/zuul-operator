#!/bin/bash

# Copyright 2021 Acme Gating, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

KIND="${KIND:-kind}"
KUBECTL="${KUBECTL:-kubectl}"
DOCKER="${DOCKER:-docker}"

$KIND delete cluster
$KIND create cluster --config kind.yaml

HEAVY=true

common_images=(
    docker.io/library/zookeeper:3.8.4
    quay.io/jetstack/cert-manager-cainjector:v1.2.0
    quay.io/jetstack/cert-manager-controller:v1.2.0
    quay.io/jetstack/cert-manager-webhook:v1.2.0
    docker.io/jettech/kube-webhook-certgen:v1.5.1
    docker.io/zuul/zuul-web:latest
    docker.io/zuul/zuul-scheduler:latest
    docker.io/zuul/zuul-executor:latest
    docker.io/zuul/zuul-preview:latest
    docker.io/zuul/zuul-registry:latest
)

heavy_images=(
    docker.io/percona/percona-xtradb-cluster-operator:1.7.0
    docker.io/percona/percona-xtradb-cluster-operator:1.7.0-haproxy
    docker.io/percona/percona-xtradb-cluster-operator:1.7.0-logcollector
    docker.io/percona/percona-xtradb-cluster:8.0.21-12.1
    docker.io/library/percona:8.0
    quay.io/containers/podman:latest
)

light_images=(
    docker.io/library/mariadb:focal
)

for img in "${common_images[@]}"; do
    $DOCKER image inspect "${img}" >/dev/null || $DOCKER pull "${img}"
    $KIND load docker-image "${img}" &
done

if [[ $HEAVY = "true" ]]; then
    for img in "${heavy_images[@]}"; do
	$DOCKER image inspect "${img}" >/dev/null || $DOCKER pull "${img}"
	$KIND load docker-image "${img}" &
    done
else
    for img in "${light_images[@]}"; do
	$DOCKER image inspect "${img}" >/dev/null || $DOCKER pull "${img}"
	$KIND load docker-image "${img}" &
    done
fi

$KIND load docker-image docker.io/zuul/zuul-operator:latest

$KUBECTL apply -f ingress.yaml &

echo "Waiting"
wait
echo "Done"
