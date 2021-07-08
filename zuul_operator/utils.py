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

import json
import secrets
import string

import kopf
import yaml
import jinja2
import kubernetes
from kubernetes.client import Configuration
from kubernetes.client.api import core_v1_api
from kubernetes.client.rest import ApiException
from kubernetes.stream import stream

from . import objects


def object_from_dict(data):
    return objects.get_object(data['apiVersion'], data['kind'])


def zuul_to_json(x):
    return json.dumps(x)


def apply_file(api, fn, **kw):
    env = jinja2.Environment(
        loader=jinja2.PackageLoader('zuul_operator', 'templates'))
    env.filters['zuul_to_json'] = zuul_to_json
    tmpl = env.get_template(fn)
    text = tmpl.render(**kw)
    data = yaml.safe_load_all(text)
    namespace = kw.get('namespace')
    for document in data:
        if namespace:
            document['metadata']['namespace'] = namespace
        if kw.get('_adopt', True):
            kopf.adopt(document)
        obj = object_from_dict(document)(api, document)
        if not obj.exists():
            obj.create()
        else:
            obj.update()


def generate_password(length=32):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for i in range(length))


def make_secret(namespace, name, string_data):
    return {
        'apiVersion': 'v1',
        'kind': 'Secret',
        'metadata': {
            'namespace': namespace,
            'name': name,
        },
        'stringData': string_data
    }


def update_secret(api, namespace, name, string_data):
    obj = make_secret(namespace, name, string_data)
    secret = objects.Secret(api, obj)
    if secret.exists():
        secret.update()
    else:
        secret.create()


def pod_exec(namespace, name, command):
    kubernetes.config.load_kube_config()
    try:
        c = Configuration().get_default_copy()
    except AttributeError:
        c = Configuration()
        c.assert_hostname = False
    Configuration.set_default(c)
    api = core_v1_api.CoreV1Api()

    resp = stream(api.connect_get_namespaced_pod_exec,
                  name,
                  namespace,
                  command=command,
                  stderr=True, stdin=False,
                  stdout=True, tty=False)
    return resp
