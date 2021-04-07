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

import copy
import base64
import hashlib

import jinja2
import pykube
import yaml

from . import objects
from . import utils
from . import certmanager
from . import pxc
from . import zookeeper


class Zuul:
    def __init__(self, namespace, name, logger, spec):
        self.api = pykube.HTTPClient(pykube.KubeConfig.from_env())
        self.namespace = namespace
        self.name = name
        self.log = logger
        self.spec = copy.deepcopy(dict(spec))
        self.zuul_conf_sha = None

        db_secret = spec.get('database', {}).get('secretName')
        if db_secret:
            self.db_secret = db_secret
            self.manage_db = False
        else:
            self.db_secret = 'zuul-db'
            self.manage_db = True

        self.nodepool_secret = spec.get('launcher', {}).get('config',{}).\
            get('secretName')

        zk_spec = self.spec.setdefault('zookeeper', {})
        zk_str = spec.get('zookeeper', {}).get('hosts')
        if zk_str:
            self.manage_zk = False
        else:
            zk_str = f'zookeeper.{self.namespace}:2281'
            zk_spec['hosts'] = zk_str
            zk_spec['secretName'] = 'zookeeper-client-tls'
            self.manage_zk = True

        zk_spec['tls_ca'] = '/tls/client/ca.crt'
        zk_spec['tls_cert'] = '/tls/client/tls.crt'
        zk_spec['tls_key'] = '/tls/client/tls.key'

        self.tenant_secret = spec.get('scheduler', {}).\
            get('config', {}).get('secretName')

        self.spec.setdefault('scheduler', {})['tenant_config'] = \
            '/etc/zuul/tenant/main.yaml'

        ex = self.spec.setdefault('executor', {})

        self.cert_manager = certmanager.CertManager(
            self.api, self.namespace, self.log)
        self.installing_cert_manager = False

    def install_cert_manager(self):
        if self.cert_manager.is_installed():
            return
        self.installing_cert_manager = True
        self.cert_manager.install()

    def wait_for_cert_manager(self):
        if not self.installing_cert_manager:
            return
        self.log.info("Waiting for Cert-Manager")
        self.cert_manager.wait_for_webhook()

    def create_cert_manager_ca(self):
        self.cert_manager.create_ca()

    def install_zk(self):
        if not self.manage_zk:
            self.log.info("ZK is externally managed")
            return
        self.zk = zookeeper.ZooKeeper(self.api, self.namespace, self.log)
        self.zk.create()

    def wait_for_zk(self):
        if not self.manage_zk:
            return
        self.log.info("Waiting for ZK cluster")
        self.zk.wait_for_cluster()

    # A two-part process for PXC so that this can run while other
    # installations are happening.
    def install_db(self):
        if not self.manage_db:
            self.log.info("DB is externally managed")
            return
        # TODO: get this from spec
        small = True

        self.log.info("DB is internally managed")
        self.pxc = pxc.PXC(self.api, self.namespace, self.log)
        if not self.pxc.is_installed():
            self.log.info("Installing PXC operator")
            self.pxc.create_operator()

        self.log.info("Creating PXC cluster")
        self.pxc.create_cluster(small)

    def wait_for_db(self):
        if not self.manage_db:
            return
        self.log.info("Waiting for PXC cluster")
        self.pxc.wait_for_cluster()

        dburi = self.get_db_uri()
        if not dburi:
            self.log.info("Creating database")
            self.pxc.create_database()

    def get_db_uri(self):
        try:
            obj = objects.Secret.objects(self.api).\
                filter(namespace=self.namespace).\
                get(name=self.db_secret)
            uri = base64.b64decode(obj.obj['data']['dburi']).decode('utf8')
            return uri
        except pykube.exceptions.ObjectDoesNotExist:
            return None

    def write_zuul_conf(self):
        dburi = self.get_db_uri()
        self.spec.setdefault('database', {})['dburi'] = dburi

        for volume in self.spec.get('jobVolumes', []):
            key = f"{volume['context']}_{volume['access']}_paths"
            paths = self.spec['executor'].get(key, '')
            if paths:
                paths += ':'
            paths += volume['path']
            self.spec['executor'][key] = paths

        connections = self.spec['connections']

        # Copy in any information from connection secrets
        for connection_name, connection in connections.items():
            if 'secretName' in connection:
                obj = objects.Secret.objects(self.api).\
                    filter(namespace=self.namespace).\
                    get(name=connection['secretName'])
                for k, v in obj.obj['data'].items():
                    if k == 'sshkey':
                        v = f'/etc/zuul/connections/{connection_name}/sshkey'
                    else:
                        v = base64.b64decode(v)
                    connection[k] = v

        kw = {'connections': connections,
              'spec': self.spec}

        env = jinja2.Environment(
            loader=jinja2.PackageLoader('zuul_operator', 'templates'))
        tmpl = env.get_template('zuul.conf')
        text = tmpl.render(**kw)

        # Create a sha of the zuul.conf so that we can set it as an
        # annotation on objects which should be recreated when it
        # changes.
        m = hashlib.sha256()
        m.update(text.encode('utf8'))
        self.zuul_conf_sha = m.hexdigest()

        utils.update_secret(self.api, self.namespace, 'zuul-config',
                            string_data={'zuul.conf': text})

    def parse_zk_string(self, hosts):
        if '/' in hosts:
            hosts, chroot = hosts.split('/', 1)
        else:
            chroot = None
        hosts = hosts.split(',')
        ret = []
        for entry in hosts:
            host, port = entry.rsplit(':', 1)
            server = {'host': host,
                      'port': port}
            if chroot:
                server['chroot'] = chroot
            ret.append(server)
        return ret

    def write_nodepool_conf(self):
        self.nodepool_provider_secrets = {}
        # load nodepool config

        if not self.nodepool_secret:
            self.log.warning("No nodepool config secret found")

        try:
            obj = objects.Secret.objects(self.api).\
                filter(namespace=self.namespace).\
                get(name=self.nodepool_secret)
        except pykube.exceptions.ObjectDoesNotExist:
            self.log.error("Nodepool config secret not found")
            return None

        # Shard the config so we can create a deployment + secret for
        # each provider.
        nodepool_yaml = yaml.safe_load(base64.b64decode(obj.obj['data']['nodepool.yaml']))

        nodepool_yaml['zookeeper-servers'] = self.parse_zk_string(
            self.spec['zookeeper']['hosts'])
        nodepool_yaml['zookeeper-tls'] = {
            'cert': '/tls/client/tls.crt',
            'key': '/tls/client/tls.key',
            'ca': '/tls/client/ca.crt',
        }
        for provider in nodepool_yaml['providers']:
            self.log.info("Configuring provider %s", provider.get('name'))

            secret_name = f"nodepool-config-{self.name}-{provider['name']}"

            provider_yaml = nodepool_yaml.copy()
            provider_yaml['providers'] = [provider]

            text = yaml.dump(provider_yaml)
            utils.update_secret(self.api, self.namespace, secret_name,
                                string_data={'nodepool.yaml': text})
            self.nodepool_provider_secrets[provider['name']] = secret_name

    def create_nodepool(self):
        # Create secrets
        self.write_nodepool_conf()

        # Create providers
        for provider_name, secret_name in\
            self.nodepool_provider_secrets.items():
            kw = {
                'zuul_version': '4.1.0',
                'instance_name': self.name,
                'provider_name': provider_name,
                'nodepool_config_secret_name': secret_name,
                'external_config': self.spec.get('externalConfig', {}),
            }
        utils.apply_file(self.api, 'nodepool-launcher.yaml',
                         namespace=self.namespace, **kw)

        # Get current providers
        providers = objects.Deployment.objects(self.api).filter(
            namespace=self.namespace,
            selector={'app.kubernetes.io/instance': self.name,
                      'app.kubernetes.io/component': 'nodepool-launcher',
                      'app.kubernetes.io/name': 'nodepool',
                      'app.kubernetes.io/part-of': 'zuul'})

        new_providers = set(self.nodepool_provider_secrets.keys())
        old_providers = set([x.labels['operator.zuul-ci.org/nodepool-provider']
                             for x in providers])
        # delete any unecessary provider deployments and secrets
        for unused_provider in old_providers - new_providers:
            self.log.info("Deleting unused provider %s", unused_provider)

            deployment_name = f"nodepool-launcher-{self.name}-{unused_provider}"
            secret_name = f"nodepool-config-{self.name}-{unused_provider}"

            try:
                obj = objects.Deployment.objects(self.api).filter(
                    namespace=self.namespace).get(deployment_name)
                obj.delete()
            except pykube.exceptions.ObjectDoesNotExist:
                pass

            try:
                obj = objects.Secret.objects(self.api).filter(
                    namespace=self.namespace).get(secret_name)
                obj.delete()
            except pykube.exceptions.ObjectDoesNotExist:
                pass

    def create_zuul(self):
        kw = {
            'zuul_conf_sha': self.zuul_conf_sha,
            'zuul_version': '4.1.0',
            'zuul_web': {
                'replicas': 3,
            },
            'zuul_executor': {
                'replicas': 3,
            },
            'zuul_tenant_secret': self.tenant_secret,
            'instance_name': self.name,
            'connections': self.spec['connections'],
            'executor_ssh_secret': self.spec['executor'].get(
                'sshkey', {}).get('secretName'),
            'spec': self.spec,
            'manage_zk': self.manage_zk,
            'manage_db': self.manage_db,
        }
        utils.apply_file(self.api, 'zuul.yaml', namespace=self.namespace, **kw)
        self.create_nodepool()

    def smart_reconfigure(self):
        self.log.info("Smart reconfigure")
        try:
            obj = objects.Secret.objects(self.api).\
                filter(namespace=self.namespace).\
                get(name=self.tenant_secret)
            tenant_config = base64.b64decode(
                obj.obj['data']['main.yaml'])
        except pykube.exceptions.ObjectDoesNotExist:
            self.log.error("Tenant config secret not found")
            return

        m = hashlib.sha256()
        m.update(tenant_config)
        conf_sha = m.hexdigest()

        expected = f"{conf_sha}  /etc/zuul/tenant/main.yaml"

        for obj in objects.Pod.objects(self.api).filter(
                namespace=self.namespace,
                selector={'app.kubernetes.io/instance': 'zuul',
                          'app.kubernetes.io/component': 'zuul-scheduler',
                          'app.kubernetes.io/name': 'zuul'}):
            self.log.info("Waiting for config to update on %s",
                          obj.name)

            delay = 10
            retries = 30
            timeout = delay * retries
            command = [
                '/usr/bin/timeout',
                str(timeout),
                '/bin/sh',
                '-c',
                f'while !( echo -n "{expected}" | sha256sum -c - ); do sleep {delay}; done'
            ]
            resp = utils.pod_exec(self.namespace, obj.name, command)
            self.log.debug("Response: %s", resp)

            if '/etc/zuul/tenant/main.yaml: OK' in resp:
                self.log.info("Issuing smart-reconfigure on %s", obj.name)
                command = [
                    'zuul-scheduler',
                    'smart-reconfigure',
                ]
                resp = utils.pod_exec(self.namespace, obj.name, command)
                self.log.debug("Response: %s", resp)
            else:
                self.log.error("Tenant config file never updated on %s",
                               obj.name)
