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

import inspect

# We deliberately import * to create a superset of objects.
from pykube.objects import *


class Issuer(NamespacedAPIObject):
    version = "cert-manager.io/v1"
    endpoint = "issuers"
    kind = "Issuer"


class Certificate(NamespacedAPIObject):
    version = "cert-manager.io/v1"
    endpoint = "certificates"
    kind = "Certificate"


class MutatingWebhookConfiguration(APIObject):
    version = 'admissionregistration.k8s.io/v1'
    endpoint = 'mutatingwebhookconfigurations'
    kind = 'MutatingWebhookConfiguration'


class ValidatingWebhookConfiguration(APIObject):
    version = 'admissionregistration.k8s.io/v1'
    endpoint = 'validatingwebhookconfigurations'
    kind = 'ValidatingWebhookConfiguration'


class CustomResourceDefinition(APIObject):
    version = "apiextensions.k8s.io/v1"
    endpoint = "customresourcedefinitions"
    kind = "CustomResourceDefinition"


class Role_v1beta1(NamespacedAPIObject):
    version = "rbac.authorization.k8s.io/v1beta1"
    endpoint = "roles"
    kind = "Role"


class PodDisruptionBudget(NamespacedAPIObject):
    version = "policy/v1"
    endpoint = "poddisruptionbudgets"
    kind = "PodDisruptionBudget"


class ClusterRole_v1beta1(APIObject):
    version = "rbac.authorization.k8s.io/v1beta1"
    endpoint = "clusterroles"
    kind = "ClusterRole"


class PerconaXtraDBCluster(NamespacedAPIObject):
    version = "pxc.percona.com/v1-11-0"
    endpoint = "perconaxtradbclusters"
    kind = "PerconaXtraDBCluster"


class ZuulObject(NamespacedAPIObject):
    version = "operator.zuul-ci.org/v1alpha2"
    endpoint = "zuuls"
    kind = "Zuul"


def get_object(version, kind):
    for obj_name, obj in globals().items():
        if not (inspect.isclass(obj) and
                issubclass(obj, APIObject) and
                hasattr(obj, 'version')):
            continue
        if obj.version == version and obj.kind == kind:
            return obj
    raise Exception(f"Unable to find object of type {kind}")
