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

from . import objects
from . import utils


class ZooKeeper:
    def __init__(self, api, namespace, logger, spec):
        self.api = api
        self.namespace = namespace
        self.log = logger
        self.spec = spec

    def create(self):
        utils.apply_file(self.api, 'zookeeper.yaml',
                         namespace=self.namespace, spec=self.spec)

    def wait_for_cluster(self):
        while True:
            count = 0
            for obj in objects.Pod.objects(self.api).filter(
                    namespace=self.namespace,
                    selector={'app': 'zookeeper',
                              'component': 'server'}):
                if obj.obj['status']['phase'] == 'Running':
                    count += 1
            if count == 3:
                self.log.info("ZK cluster is running")
                return
            else:
                self.log.info(f"Waiting for ZK cluster: {count}/3")
                time.sleep(10)
