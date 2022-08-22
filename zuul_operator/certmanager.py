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

import time

import pykube

from . import objects
from . import utils


class CertManager:
    def __init__(self, api, namespace, logger):
        self.api = api
        self.namespace = namespace
        self.log = logger

    def is_installed(self):
        kind = objects.get_object('apiextensions.k8s.io/v1',
                                  'CustomResourceDefinition')
        try:
            kind.objects(self.api).\
                get(name="certificaterequests.cert-manager.io")
        except pykube.exceptions.ObjectDoesNotExist:
            return False
        return True

    def install(self):
        utils.apply_file(self.api, 'cert-manager.yaml', _adopt=False)

    def create_ca(self):
        utils.apply_file(self.api, 'cert-authority.yaml',
                         namespace=self.namespace)

    def wait_for_webhook(self):
        while True:
            count = 0
            for obj in objects.Pod.objects(self.api).filter(
                    namespace='cert-manager',
                    selector={'app.kubernetes.io/component': 'webhook',
                              'app.kubernetes.io/instance': 'cert-manager'}):
                if obj.obj['status']['phase'] == 'Running':
                    count += 1
            if count > 0:
                self.log.info("Cert-manager is running")
                return
            else:
                self.log.info("Waiting for Cert-manager")
                time.sleep(10)
