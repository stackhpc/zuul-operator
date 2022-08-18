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

import argparse

import kopf

from zuul_operator import ZuulOperator


class ZuulOperatorCommand:
    def __init__(self):
        self.op = ZuulOperator()

    def _get_version(self):
        from zuul_operator.version import version_info as version_info
        return "Zuul Operator version: %s" % version_info.release_string()

    def run(self):
        parser = argparse.ArgumentParser(
            description='Zuul Operator',
            formatter_class=argparse.RawDescriptionHelpFormatter)
        parser.add_argument('--version', dest='version', action='version',
                            version=self._get_version())
        parser.add_argument('-d', dest='debug', action='store_true',
                            help='enable debug log')
        args = parser.parse_args()

        # Use kopf's loggers since they carry object data
        kopf.configure(debug=False, verbose=args.debug,
                       quiet=False,
                       log_format=kopf.LogFormat['FULL'],
                       log_refkey=None, log_prefix=None)

        self.op.run()


def main():
    zo = ZuulOperatorCommand()
    zo.run()
