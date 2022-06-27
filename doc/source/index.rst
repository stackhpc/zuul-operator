Zuul Operator
=============

This is a Kubernetes Operator for the Zuul Project Gating System.

Zuul has a number of components and depencencies, and this operator is
designed to simplify creating and maintaining Zuul systems in
Kubernetes.

Somewhat unusually, this operator offers the ability to completely
manage Zuul's operational dependencies, to the point of even
installing other operators upon which it relies.  Be sure to read
about deployment options if you want to perform some of these tasks
yourself.

Simple Example
--------------

The quickest way to get a running Zuul is to allow the operator to
manage all of the dependencies for you.  In this case, the operator
will:

* Install cert-manager and set up a self-signed cluster issuer
* Install the Percona XtraDB operator and create a three-node PXC
  database cluster
* Create a three-node ZooKeeper cluster
* And of course, create a Zuul system

.. note::

   Installing other operators requires a high level of access, so when
   used in this manner, zuul-operator runs with cluster admin
   privileges.  If you would like the operator to run with reduced
   privileges, see Managing Operator Dependencies.

From the root of the zuul-operator repo, run:

.. code-block:: bash

   kubectl apply -f deploy/crds/zuul-ci_v1alpha1_zuul_crd.yaml
   kubectl apply -f deploy/rbac-admin.yaml
   kubectl apply -f deploy/operator.yaml

You probably want a namespace, so go ahead and create one with:

.. code-block:: bash

   kubectl create namespace zuul

You will need to prepare two config files for Zuul: the Nodepool
config file and the Zuul tenant config file.  See the Zuul and
Nodepool manuals for how to prepare those.  When they are ready, add
them to Kubernetes with commands like:

.. code-block:: bash

   kubectl -n zuul create secret generic zuul-nodepool-config --from-file=nodepool.yaml
   kubectl -n zuul create secret generic zuul-tenant-config --from-file=main.yaml

Then create a file called ``zuul.yaml`` which looks like:

.. code-block:: yaml

   ---
   apiVersion: operator.zuul-ci.org/v1alpha2
   kind: Zuul
   metadata:
     name: zuul
   spec:
     executor:
       count: 1
       sshkey:
         secretName: gerrit-secrets
     scheduler:
       config:
         secretName: zuul-tenant-config
     launcher:
       config:
         secretName: zuul-nodepool-config
     web:
       count: 1
     connections:
       opendev:
         driver: git
         baseurl: https://opendev.org

This will create the most basic of Zuul installations, with one each
of the `zuul-executor`, `zuul-scheduler`, and `zuul-web` processes.
It will also create a Nodepool launcher for each of the providers
listed in your ``nodepool.yaml``.  If your Zuul tenant config file
requires more connections, be sure to add them here.

Managing Operator Dependencies
------------------------------

You may not want zuul-operator to install other operators (for
example, if your cluster has other users and you don't want
cert-manager or pxc-operator to be tied to a Zuul installation, or if
you would prefer to avoid granting zuul-operator cluster admin
privileges).  In that case, you may install the other operators
yourself and still allow zuul-operator to use those other operators.
It can still create a PXC cluster for you as long as the pxc-operator
is present.

To use this mode of operation, make sure the following dependencies
are installed before using zuul-operator:

* Cert-manager (at least version 1.2.0)
* Percona-xtradb-cluster-operator (at least version 1.7.0)

With these installed, you may install zuul-operator with reduced
privileges:

.. code-block:: bash

   kubectl apply -f deploy/crds/zuul-ci_v1alpha1_zuul_crd.yaml
   kubectl apply -f deploy/rbac.yaml
   kubectl apply -f deploy/operator.yaml

After this point, usage is the same as other methods.

Externally Managed Zuul Dependencies
------------------------------------

If you want zuul-operator to do even less work, you can have it avoid
managing either ZooKeeper or the SQL database.

Externally Managed ZooKeeper
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you already have a ZooKeeper instance you would like Zuul to use,
add the following to the `Zuul` spec:

.. code-block:: yaml

   ---
   apiVersion: operator.zuul-ci.org/v1alpha2
   kind: Zuul
   spec:
     zookeeper:
        connectionString: ...
        secretName: ...

The ``connectionString`` field should be a standard ZooKeeper
connection string, and the ``secretName`` field should be a Kubernetes
TLS secret with the client cert for Zuul to use when connecting to
ZooKeeper.  TLS is required.

Externally Managed Database
~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you would like to use an existing database, add the following to
the `Zuul` spec:

.. code-block:: yaml

   ---
   apiVersion: operator.zuul-ci.org/v1alpha2
   kind: Zuul
   spec:
     database:
        dburi: ...

The ``dburi`` field should contain a Python db-api URI; it corresponds
to the ``dburi`` entry in ``zuul.conf``.

Secrets
-------

The operator uses Kubernetes secrets as input values for several
aspects of operation.  There are some general rules about how secrets
are used:

* For configuration files, secret keys are expected to be the typical
  filename (for example, ``nodepool.yaml`` for the Nodepool config
  file).

* For Zuul connection entries, secret keys correspond to the
  configuration file attributes for that section (e.g., ``app_key``
  for the github driver).

See the reference documentation for the specific `secretName` entry
for details.

Zuul Preview
------------

The operator has optional support for deploying a zuul-preview
service.  This is an experimental add-on for Zuul to serve Zuul
artifacts from the root of a domain (this can be useful for serving
static HTML/Javascript sites).  If you enable this, the operator will
configure a ``zuul-preview`` service to which you may route an Ingress
or LoadBalancer.

Zuul Registry
-------------

The operator has optional support for deploying a zuul-registry
service.  This is an experimental add-on for Zuul to act as an
intermediate registry for the container image jobs in `zuul-jobs`.

If you enable this, the operator will, by default, configure a
``zuul-registry`` service in a manner appropriate for access from
within the cluster only.  If you need to access the registry from
outside the cluster, you will need to additionally add an Ingress or
LoadBalancer, as well as provide TLS certs with the appropriate
hostname.  Currently, zuul-registry performs its own TLS termination.

If you usue this, you will also need to provide a ``registry.yaml``
config file in a secret.  You only need to provide the ``users`` and,
if you are accessing the registry outside the cluster, the
``public-url`` setting (omit it if you are accessing it from within
the cluster only).

.. code-block:: yaml

   registry:
     users:
       - name: testuser
         pass: testpass
         access: write

Specification Reference
-----------------------

This is a fully populated example (with the exception of connection
entries which can contain `zuul.conf` attributes passed through
verbatim):

.. code-block:: yaml

   apiVersion: zuul-ci.org/v1alpha2
   kind: Zuul
   spec:
     imagePrefix: docker.io/zuul
     imagePullSecrets:
       - name: my-docker-secret
     zuulImageVersion: latest
     zuulPreviewImageVersion: latest
     zuulRegistryImageVersion: latest
     nodepoolImageVersion: latest
     database:
       secretName: mariadbSecret
     zookeeper:
       hosts: zk.example.com:2282
       secretName: zookeeperTLS
     merger:
       count: 5
       git_user_email: zuul@example.org
       git_user_name: Example Zuul
     executor:
       count: 5
       manage_ansible: false
     web:
       count: 1
       status_url: https://zuul.example.org
     fingergw:
       count: 1
     scheduler:
       count: 1
     connections:
       gerrit:
         driver: gerrit
         server: gerrit.example.com
         secretName: gerritSecrets
         user: zuul
         baseurl: http://gerrit.example.com:8080
       github:
         driver: github
         secretName: githubSecrets
         rate_limit_logging: false
         app_id: 1234
     jobVolumes:
       - context: trusted
         access: ro
         path: /authdaemon/token
         volume:
           name: gcp-auth
           hostPath:
             path: /var/authdaemon/executor
             type: DirectoryOrCreate

.. attr:: Zuul

   The Zuul kind is currently the only resource directly handled by
   the operator.  It holds a complete description of a Zuul system
   (though at least partly via secrets referenced by this resource).

   .. attr:: spec

      .. attr:: imagePrefix
         :default: docker.io/zuul

         The prefix to use for images.  The image names are fixed
         (``zuul-executor``, etc).  However, changing the prefix will
         allow you to use custom images or private registries.

      .. attr:: imagePullSecrets
         :type: list
         :default: []

         If supplied, this value is passed through to Kubernetes.  It
         should be a list of secrets.

         .. attr:: name

            The name of the image pull secret.

      .. attr:: zuulImageVersion
         :default: latest

         The image tag to append to the Zuul images.

      .. attr:: zuulPreviewImageVersion
         :default: latest

         The image tag to append to the Zuul Preview images.

      .. attr:: zuulRegistryImageVersion
         :default: latest

         The image tag to append to the Zuul Registry images.

      .. attr:: nodepoolImageVersion
         :default: latest

         The image tag to append to the Nodepool images.

      .. attr:: database

         This is not required unless you want to manage the database
         yourself.  If you omit this section, zuul-operator will
         create a Percona XtraDB cluster for you.

         You may add any attribute corresponding to the `database`
         section of zuul.conf here.  The ``dburi`` attribute will come
         from the secret below.

         .. attr:: secretName

            The name of a secret containing connection information for
            the database.

            The key name in the secret should be ``dburi``.

         .. attr:: allowUnsafeConfig
            :default: False

            If you are running in a resource constrained environment
            (such as minikube), the requested resource values for the
            Percona XtraDB may be too large.  Set this to True to
            override the default values and construct the cluster
            regardless.  Only use this for testing.

      .. attr:: zookeeper

         This is not required unless you want to manage the ZooKeeper
         cluster yourself.  If you omit this section, zuul-operator
         will create a ZooKeeper cluster for you

         You may add any attribute corresponding to the `zookeeper`
         section of zuul.conf here.  The ``hosts`` and TLS attributes
         will come from the secret below.

         .. attr:: hosts

            A standard ZooKeeper connection string.

         .. attr:: secretName

            The name of a secret containing a TLS client certificate
            and key for ZooKeeper.  This should be (or the format
            should match) a standard Kubernetes TLS secret.

            The key names in the secret should be:

            * ``ca.crt``
            * ``tls.crt``
            * ``tls.key``

      .. attr:: env

         A list of environment variables.  This will be passed through
         to the Pod specifications for the scheduler, launcher, and
         web.  This may be used to set http_proxy environment
         variables.

      .. attr:: scheduler

         .. attr:: config

            .. attr:: secretName

               The name of a secret containing the Zuul tenant config
               file.

               The key name in the secret should be ``main.yaml``.

      .. attr:: launcher

         .. attr:: config

            .. attr:: secretName

               The name of a secret containing the Nodepool config
               file.

               The key name in the secret should be ``nodepool.yaml``.

      .. attr:: executor

         .. attr:: count
            :default: 1

            How many executors to manage.  This is a required
            component and should be at least 1.

         .. attr:: sshkey

            .. attr:: secretName

               The name of a secret containing the SSH private key
               that executors should use when logging into Nodepool
               nodes.  You will need to arrange for the public half of
               this key to be installed on those nodes via whatever
               mechanism provided by your cloud.

               The key name in the secret should be ``sshkey``.

         .. attr:: terminationGracePeriodSeconds
            :default: 21600

            When performing a rolling restart of the executors, wait
            this long for jobs to finish normally.  If an executor
            takes longer than this amount of time, it will be
            hard-stopped (and jobs will abort and retry).  The default
            is 6 hours, but depending on the workload, a higher or
            lower value may be appropriate.

      .. attr:: merger

         .. attr:: count
            :default: 0

            How many mergers to manage.  Executors also act as mergers
            so this is not required.  They may be useful on a busy
            system.

      .. attr:: web

         .. attr:: count
            :default: 1

            How many Zuul webservers to manage.  This is a required
            component and should be at least 1.

      .. attr:: fingergw

         .. attr:: count
            :default: 1

            How many Zuul finger gateway servers to manage.

      .. attr:: connections

         This is a mapping designed to match the `connections` entries
         in the main Zuul config file (`zuul.conf`).  Each key in the
         mapping is the name of a connection (this is the name you
         will use in the tenant config file), and the values are
         key/value pairs that are directly added to that connectien
         entry in `zuul.conf`.  In the case of keys which are
         typically files (for example, SSH keys), the values will be
         written to disk for you (so you should include the full
         values here and not the path).

         You may provide any of these values directly in this resource
         or using the secret described below.  You may use both, and
         the values will be combined (for example, you may include all
         the values here except a private key which you include in a
         secret).

         Example:

         .. code-block:: yaml

            connections:
              opendev:
                driver: git
                baseurl: https://opendev.org
              gerrit:
                driver: git
                baseurl: https://gerrit.examplec.mo
                secretName: gerrit-secrets

         .. attr:: <name>

            The name of the connection.  You will use this is the
            tenant config file.  All of the attributes describing this
            connection should be included underneath this key.

            .. attr:: secretName

               The name of a secret describing this connection.  All
               of the keys and values in this secret will be merged
               with the keys and values described in this connection
               entry.  If you need to provide a file (for example, the
               ``sshkey`` attribute of a Gerrit connection), include
               the contents as the value of the ``sshkey`` attribute
               in the secret.

      .. attr:: externalConfig

         A mapping of secrets for specific Nodepool drivers.  Some
         Nodepool drivers use external files for configuration (e.g.,
         `clouds.yaml` for OpenStack).  To provide these to Nodepool,
         add them to a secret and specify the name of that secret in
         an entry in externalConfig.

         For example, a secret for OpenStack might look like:

         .. code-block:: yaml

            apiVersion: v1
            kind: Secret
            metadata:
              name: openstack-secret
            stringData:
              clouds.yaml: "..."

         To use that with Nodepool, add the following to the Operator
         resource definition:

         .. code-block:: yaml

            externalConfig:
              openstack:
                secretName: openstack-secret

         This will cause a `clouds.yaml` file to be created at
         `/etc/openstack/clouds.yaml`.

         Some Nodepool drivers may need environment variables set in
         order to use these secrets.  See :attr:`Zuul.spec.env` to add
         those.

         The keys in this mapping will become directories under
         `/etc/`, and the secrets referenced will be mounted in those
         directories.

         .. attr:: <name>

            The directory to mount under `/etc`.

            .. attr:: SecretName

               The name of a secret that should be mounted at `/etc/<name>`.

      .. attr:: jobVolumes

         A list of Kubernetes volumes to be bind mounted into the
         executor's execution context.  These correspond to the
         `trusted_ro_paths`, `untrusted_ro_paths`, `trusted_rw_paths`,
         and `untrusted_ro_paths` entries in `zuul.conf`.

         The first part of each entry describes how the volume should
         appear in the executor, and the `volume` attribute describes
         the Kubernetes volume.

         .. attr:: context

            One of the following values:

            .. value:: trusted

               To be mounted in the `trusted` execution context.

            .. value:: untrusted

               To be mounted in the `untrusted` execution context.

         .. attr:: access

            One of the following values:

            .. value:: rw

               To be mounted read/write.

            .. value:: ro

               To be mounted read-only.

         .. attr:: path

            The mount point within the execution context.

         .. attr:: volume

            A mapping corresponding to a Kubernetes volume.

      .. attr:: preview

         .. attr:: count
            :default: 0

            How many Zuul Preview servers to manage.

      .. attr:: registry

         .. attr:: count
            :default: 0

            How many Zuul Registry servers to manage.

         .. attr:: volumeSize
            :default: 80G

            The requested size of the registry storage volume.

         .. attr:: tls

            .. attr:: secretName

               The name of a secret containing a TLS client certificate
               and key for Zuul Registry.  This should be (or the format
               should match) a standard Kubernetes TLS secret.

               If you omit this, the operator will create a secret for
               you.

         .. attr:: config

            .. attr:: secretName

               The name of a secret containing a registry
               configuration file.  The key in the secret should be
               ``registry.yaml``.  Only provide the ``users`` and, if
               exposing the registry outside the cluster, the
               ``public-url`` entries.
