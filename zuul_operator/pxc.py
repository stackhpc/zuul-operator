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
import base64

import pykube

from . import objects
from . import utils


class PXC:
    def __init__(self, api, namespace, logger):
        self.api = api
        self.namespace = namespace
        self.log = logger

    def is_installed(self):
        kind = objects.get_object('apiextensions.k8s.io/v1',
                                  'CustomResourceDefinition')
        try:
            kind.objects(self.api).\
                get(name="perconaxtradbclusters.pxc.percona.com")
        except pykube.exceptions.ObjectDoesNotExist:
            return False
        return True

    def create_operator(self):
        # We don't adopt this so that the operator can continue to run
        # after the pxc cr is deleted; if we did adopt it, then when
        # the zuul cr is deleted, the operator would be immediately
        # deleted and the cluster orphaned.  Basically, we get to
        # choose whether to orphan the cluster or the operator, and
        # the operator seems like the better choice.
        utils.apply_file(self.api, 'pxc-bundle.yaml', _adopt=False)

    def create_cluster(self, small):
        kw = {'namespace': self.namespace}
        kw['anti_affinity_key'] = small and 'none' or 'kubernetes.io/hostname'
        kw['allow_unsafe'] = small and True or False

        utils.apply_file(self.api, 'pxc-cluster.yaml', **kw)

    def wait_for_cluster(self):
        while True:
            count = 0
            for obj in objects.Pod.objects(self.api).filter(
                    namespace=self.namespace,
                    selector={'app.kubernetes.io/instance': 'db-cluster',
                              'app.kubernetes.io/component': 'pxc',
                              'app.kubernetes.io/name':
                              'percona-xtradb-cluster'}):
                if obj.obj['status']['phase'] == 'Running':
                    count += 1
            if count == 3:
                self.log.info("Database cluster is running")
                return
            else:
                self.log.info(f"Waiting for database cluster: {count}/3")
                time.sleep(10)

    def get_root_password(self):
        obj = objects.Secret.objects(self.api).\
            filter(namespace=self.namespace).\
            get(name="db-cluster-secrets")

        pw = base64.b64decode(obj.obj['data']['root']).decode('utf8')
        return pw

    def create_database(self):
        root_pw = self.get_root_password()
        zuul_pw = utils.generate_password()

        utils.apply_file(self.api, 'pxc-create-db.yaml',
                         namespace=self.namespace,
                         root_password=root_pw,
                         zuul_password=zuul_pw)

        while True:
            obj = objects.Job.objects(self.api).\
                filter(namespace=self.namespace).\
                get(name='create-database')
            if obj.obj['status'].get('succeeded'):
                break
            time.sleep(2)

        obj.delete(propagation_policy="Foreground")

        dburi = f'mysql+pymysql://zuul:{zuul_pw}@db-cluster-haproxy/zuul'
        utils.update_secret(self.api, self.namespace, 'zuul-db',
                            string_data={'dburi': dburi})

        return dburi
