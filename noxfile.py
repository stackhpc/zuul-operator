# Copyright 2022 Acme Gating, LLC
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

import os

import nox


nox.options.error_on_external_run = True
nox.options.reuse_existing_virtualenvs = True
nox.options.sessions = ["tests-3", "linters"]


def set_env(session, var, default):
    session.env[var] = os.environ.get(var, default)


def set_standard_env_vars(session):
    set_env(session, 'OS_LOG_CAPTURE', '1')
    set_env(session, 'OS_STDERR_CAPTURE', '1')
    set_env(session, 'OS_STDOUT_CAPTURE', '1')
    set_env(session, 'OS_TEST_TIMEOUT', '360')

    # Set PYTHONTRACEMALLOC to a value greater than 0 in the calling env
    # to get tracebacks of that depth for ResourceWarnings. Disabled by
    # default as this consumes more resources and is slow.
    set_env(session, 'PYTHONTRACEMALLOC', '0')


@nox.session(python='3')
def docs(session):
    set_standard_env_vars(session)
    session.install('-r', 'doc/requirements.txt')
    session.install('-e', '.')
    session.run('sphinx-build', '-E', '-W', '-d', 'doc/build/doctrees',
                '-b', 'html', 'doc/source/', 'doc/build/html')
