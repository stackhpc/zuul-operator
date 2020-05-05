{- Zuul CR kubernetes resources

The evaluation of that file is a function that takes the cr inputs as an argument,
and returns the list of kubernetes of objects.

Unless cert-manager usage is enabled, the resources expect those secrets to be available:

* `${name}-gearman-tls` with:
  * `ca.crt`
  * `tls.crt`
  * `tls.key`

* `${name}-registry-tls` with:

  * `tls.crt`
  * `tls.key`


The resources expect those secrets to be available:

* `${name}-zookeeper-tls` with:

  * `ca.crt`
  * `tls.crt`
  * `tls.key`
  * `zk.pem` the keystore

* `${name}-registry-user-rw` with:

  * `secret` a password
  * `username` the user name with write access
  * `password` the user password


Unless the input.database db uri is provided, the resources expect this secret to be available:

* `${name}-database-password` the internal database password.
-}
let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let CertManager = ../CertManager.dhall

let Schemas = ./input.dhall

let F = ./functions.dhall

let Input = Schemas.Input.Type

let JobVolume = Schemas.JobVolume.Type

let UserSecret = Schemas.UserSecret.Type

let Volume = F.Volume

in      \(input : Input)
    ->  let zk-conf =
              merge
                { None =
                    { ServiceVolumes =
                      [ Volume::{
                        , name = "${input.name}-secret-zk"
                        , dir = "/conf-tls"
                        , files =
                          [ { path = "zoo.cfg"
                            , content = ./files/zoo.cfg.dhall "/conf" "/conf"
                            }
                          ]
                        }
                      ]
                    , ClientVolumes =
                      [ Volume::{
                        , name = "${input.name}-zookeeper-tls"
                        , dir = "/etc/zookeeper-tls"
                        }
                      ]
                    , Zuul =
                        ''
                        hosts=zk:2281
                        tls_cert=/etc/zookeeper-tls/tls.crt
                        tls_key=/etc/zookeeper-tls/tls.key
                        tls_ca=/etc/zookeeper-tls/ca.crt
                        ''
                    , Nodepool =
                        ''
                        zookeeper-servers:
                          - host: zk
                            port: 2281
                        zookeeper-tls:
                            cert: /etc/zookeeper-tls/tls.crt
                            key: /etc/zookeeper-tls/tls.key
                            ca: /etc/zookeeper-tls/ca.crt
                        ''
                    , Env = [] : List Kubernetes.EnvVar.Type
                    }
                , Some =
                        \(some : UserSecret)
                    ->  let empty = [] : List Volume.Type

                        in  { ServiceVolumes = empty
                            , ClientVolumes = empty
                            , Zuul = "hosts=%(ZUUL_ZK_HOSTS)"
                            , Nodepool =
                                ''
                                zookeeper-servers:
                                  - hosts: %(ZUUL_ZK_HOSTS)"
                                ''
                            , Env =
                                F.mkEnvVarSecret
                                  [ { name = "ZUUL_ZK_HOSTS"
                                    , secret = some.secretName
                                    , key = F.defaultText some.key "hosts"
                                    }
                                  ]
                            }
                }
                input.zookeeper

        let db-internal-password-env =
                  \(env-name : Text)
              ->  F.mkEnvVarSecret
                    [ { name = env-name
                      , secret = "${input.name}-database-password"
                      , key = "password"
                      }
                    ]

        let org =
              merge
                { None = "docker.io/zuul", Some = \(prefix : Text) -> prefix }
                input.imagePrefix

        let version = "latest"

        let image = \(name : Text) -> "${org}/${name}:${version}"

        let set-image =
                  \(default-name : Text)
              ->  \(input-name : Optional Text)
              ->  { image =
                      merge
                        { None = Some default-name
                        , Some = \(_ : Text) -> input-name
                        }
                        input-name
                  }

        let etc-zuul =
              Volume::{
              , name = input.name ++ "-secret-zuul"
              , dir = "/etc/zuul"
              , files =
                [ { path = "zuul.conf"
                  , content = ./files/zuul.conf.dhall input zk-conf.Zuul
                  }
                ]
              }

        let etc-zuul-registry =
              Volume::{
              , name = input.name ++ "-secret-registry"
              , dir = "/etc/zuul"
              , files =
                [ { path = "registry.yaml"
                  , content =
                      let public-url =
                            F.defaultText
                              input.registry.public-url
                              "https://registry:9000"

                      in  ./files/registry.yaml.dhall public-url
                  }
                ]
              }

        let etc-nodepool =
              Volume::{
              , name = input.name ++ "-secret-nodepool"
              , dir = "/etc/nodepool"
              , files =
                [ { path = "nodepool.yaml"
                  , content = ./files/nodepool.yaml.dhall zk-conf.Nodepool
                  }
                ]
              }

        let Components =
              { CertManager =
                  let issuer =
                        { kind = "Issuer"
                        , group = "cert-manager.io"
                        , name = "${input.name}-ca"
                        }

                  let registry-enabled =
                            Natural/isZero (F.defaultNat input.registry.count 0)
                        ==  False

                  let registry-cert =
                              if registry-enabled

                        then  [ CertManager.Certificate::{
                                , metadata =
                                    F.mkObjectMeta
                                      "${input.name}-registry-tls"
                                      ( F.mkComponentLabel
                                          input.name
                                          "cert-registry"
                                      )
                                , spec = CertManager.CertificateSpec::{
                                  , secretName = "${input.name}-registry-tls"
                                  , issuerRef = issuer
                                  , dnsNames = Some [ "registry" ]
                                  , usages = Some
                                    [ "server auth", "client auth" ]
                                  }
                                }
                              ]

                        else  [] : List CertManager.Certificate.Type

                  in  { Issuers =
                        [ CertManager.Issuer::{
                          , metadata =
                              F.mkObjectMeta
                                "${input.name}-selfsigning"
                                ( F.mkComponentLabel
                                    input.name
                                    "issuer-selfsigning"
                                )
                          , spec = CertManager.IssuerSpec::{
                            , selfSigned = Some {=}
                            }
                          }
                        , CertManager.Issuer::{
                          , metadata =
                              F.mkObjectMeta
                                "${input.name}-ca"
                                (F.mkComponentLabel input.name "issuer-ca")
                          , spec = CertManager.IssuerSpec::{
                            , ca = Some { secretName = "${input.name}-ca" }
                            }
                          }
                        ]
                      , Certificates =
                            [ CertManager.Certificate::{
                              , metadata =
                                  F.mkObjectMeta
                                    "${input.name}-ca"
                                    (F.mkComponentLabel input.name "cert-ca")
                              , spec = CertManager.CertificateSpec::{
                                , secretName = "${input.name}-ca"
                                , isCA = Some True
                                , commonName = Some "selfsigned-root-ca"
                                , issuerRef =
                                        issuer
                                    //  { name = "${input.name}-selfsigning" }
                                , usages = Some
                                  [ "server auth", "client auth", "cert sign" ]
                                }
                              }
                            , CertManager.Certificate::{
                              , metadata =
                                  F.mkObjectMeta
                                    "${input.name}-gearman-tls"
                                    ( F.mkComponentLabel
                                        input.name
                                        "cert-gearman"
                                    )
                              , spec = CertManager.CertificateSpec::{
                                , secretName = "${input.name}-gearman-tls"
                                , issuerRef = issuer
                                , dnsNames = Some [ "gearman" ]
                                , usages = Some [ "server auth", "client auth" ]
                                }
                              }
                            ]
                          # registry-cert
                      }
              , Backend =
                  { Database =
                      merge
                        { None =
                            ./components/Database.dhall
                              input.name
                              db-internal-password-env
                        , Some =
                                \(some : UserSecret)
                            ->  F.KubernetesComponent.default
                        }
                        input.database
                  , ZooKeeper =
                      merge
                        { None =
                            ./components/ZooKeeper.dhall
                              input.name
                              (zk-conf.ClientVolumes # zk-conf.ServiceVolumes)
                        , Some =
                                \(some : UserSecret)
                            ->  F.KubernetesComponent.default
                        }
                        input.zookeeper
                  }
              , Zuul =
                  let zuul-image =
                        \(name : Text) -> set-image (image "zuul-${name}")

                  let zuul-env =
                        F.mkEnvVarValue (toMap { HOME = "/var/lib/zuul" })

                  let db-secret-env =
                        merge
                          { None = db-internal-password-env "ZUUL_DB_PASSWORD"
                          , Some =
                                  \(some : UserSecret)
                              ->  F.mkEnvVarSecret
                                    [ { name = "ZUUL_DB_URI"
                                      , secret = some.secretName
                                      , key = F.defaultText some.key "db_uri"
                                      }
                                    ]
                          }
                          input.database

                  let {- executor and merger do not need database info, but they fail to parse config without the env variable
                      -} db-nosecret-env =
                        F.mkEnvVarValue (toMap { ZUUL_DB_PASSWORD = "unused" })

                  let zuul-data-dir =
                        [ Volume::{ name = "zuul-data", dir = "/var/lib/zuul" }
                        ]

                  let sched-config =
                        Volume::{
                        , name = input.scheduler.config.secretName
                        , dir = "/etc/zuul-scheduler"
                        }

                  let gearman-config =
                        Volume::{
                        , name = input.name ++ "-gearman-tls"
                        , dir = "/etc/zuul-gearman"
                        }

                  let executor-ssh-key =
                        Volume::{
                        , name = input.executor.ssh_key.secretName
                        , dir = "/etc/zuul-executor"
                        }

                  let zuul-volumes =
                        [ etc-zuul, gearman-config ] # zk-conf.ClientVolumes

                  in  { Scheduler =
                          ./components/Scheduler.dhall
                            input.name
                            (     input.scheduler
                              //  zuul-image "scheduler" input.scheduler.image
                            )
                            zuul-data-dir
                            (zuul-volumes # [ sched-config ])
                            (zuul-env # db-secret-env # zk-conf.Env)
                      , Executor =
                          ./components/Executor.dhall
                            input.name
                            (     input.executor
                              //  zuul-image "executor" input.executor.image
                            )
                            zuul-data-dir
                            (zuul-volumes # [ executor-ssh-key ])
                            (zuul-env # db-nosecret-env)
                            input.jobVolumes
                      , Web =
                          ./components/Web.dhall
                            input.name
                            (input.web // zuul-image "web" input.web.image)
                            zuul-data-dir
                            zuul-volumes
                            (zuul-env # db-secret-env # zk-conf.Env)
                      , Merger =
                          ./components/Merger.dhall
                            input.name
                            (     input.merger
                              //  zuul-image "merger" input.merger.image
                            )
                            zuul-data-dir
                            zuul-volumes
                            (zuul-env # db-nosecret-env)
                      , Registry =
                          ./components/Registry.dhall
                            input.name
                            (     input.registry
                              //  zuul-image "registry" input.registry.image
                            )
                            zuul-data-dir
                            [ etc-zuul-registry ]
                      , Preview =
                          ./components/Preview.dhall
                            input.name
                            (     input.preview
                              //  zuul-image "preview" input.preview.image
                            )
                            zuul-data-dir
                      }
              , Nodepool =
                  let nodepool-image =
                        \(name : Text) -> Some (image ("nodepool-" ++ name))

                  let nodepool-data-dir =
                        [ Volume::{
                          , name = "nodepool-data"
                          , dir = "/var/lib/nodepool"
                          }
                        ]

                  let nodepool-config =
                        Volume::{
                        , name = input.launcher.config.secretName
                        , dir = "/etc/nodepool-config"
                        }

                  let openstack-config =
                        merge
                          { None = [] : List Volume.Type
                          , Some =
                                  \(some : UserSecret)
                              ->  [ Volume::{
                                    , name = some.secretName
                                    , dir = "/etc/nodepool-openstack"
                                    }
                                  ]
                          }
                          input.externalConfig.openstack

                  let kubernetes-config =
                        merge
                          { None = [] : List Volume.Type
                          , Some =
                                  \(some : UserSecret)
                              ->  [ Volume::{
                                    , name = some.secretName
                                    , dir = "/etc/nodepool-kubernetes"
                                    }
                                  ]
                          }
                          input.externalConfig.kubernetes

                  let nodepool-env =
                        F.mkEnvVarValue
                          ( toMap
                              { HOME = "/var/lib/nodepool"
                              , OS_CLIENT_CONFIG_FILE =
                                      "/etc/nodepool-openstack/"
                                  ++  F.defaultKey
                                        input.externalConfig.openstack
                                        "clouds.yaml"
                              , KUBECONFIG =
                                      "/etc/nodepool-kubernetes/"
                                  ++  F.defaultKey
                                        input.externalConfig.kubernetes
                                        "kube.config"
                              }
                          )

                  let nodepool-volumes =
                          [ etc-nodepool, nodepool-config ]
                        # openstack-config
                        # kubernetes-config
                        # zk-conf.ClientVolumes

                  let shard-config =
                        "cat /etc/nodepool/nodepool.yaml /etc/nodepool-config/*.yaml > /var/lib/nodepool/config.yaml; "

                  in  { Launcher = F.KubernetesComponent::{
                        , Deployment = Some
                            ( F.mkDeployment
                                input.name
                                F.Component::{
                                , name = "launcher"
                                , count = 1
                                , data-dir = nodepool-data-dir
                                , volumes = nodepool-volumes
                                , container = Kubernetes.Container::{
                                  , name = "launcher"
                                  , image = nodepool-image "launcher"
                                  , args = Some
                                    [ "sh"
                                    , "-c"
                                    ,     shard-config
                                      ++  "nodepool-launcher -d -c /var/lib/nodepool/config.yaml"
                                    ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , env = Some nodepool-env
                                  , volumeMounts = Some
                                      ( F.mkVolumeMount
                                          (nodepool-volumes # nodepool-data-dir)
                                      )
                                  }
                                }
                            )
                        }
                      }
              }

        let mkSecret =
                  \(volume : Volume.Type)
              ->  Kubernetes.Resource.Secret
                    Kubernetes.Secret::{
                    , metadata = Kubernetes.ObjectMeta::{ name = volume.name }
                    , stringData = Some
                        ( Prelude.List.map
                            { path : Text, content : Text }
                            { mapKey : Text, mapValue : Text }
                            (     \(config : { path : Text, content : Text })
                              ->  { mapKey = config.path
                                  , mapValue = config.content
                                  }
                            )
                            volume.files
                        )
                    }

        let {- This function transforms the different types into the Kubernetes.Resource
               union to enable using them inside a single List array
            -} mkUnion =
                  \(component : F.KubernetesComponent.Type)
              ->  let empty = [] : List Kubernetes.Resource

                  in    merge
                          { None = empty
                          , Some =
                                  \(some : Kubernetes.Service.Type)
                              ->  [ Kubernetes.Resource.Service some ]
                          }
                          component.Service
                      # merge
                          { None = empty
                          , Some =
                                  \(some : Kubernetes.StatefulSet.Type)
                              ->  [ Kubernetes.Resource.StatefulSet some ]
                          }
                          component.StatefulSet
                      # merge
                          { None = empty
                          , Some =
                                  \(some : Kubernetes.Deployment.Type)
                              ->  [ Kubernetes.Resource.Deployment some ]
                          }
                          component.Deployment

        let {- This function transform the Kubernetes.Resources type into the new Union
               that combines Kubernetes and CertManager resources
            -} transformKubernetesResource =
              Prelude.List.map
                Kubernetes.Resource
                CertManager.Union
                (     \(resource : Kubernetes.Resource)
                  ->  CertManager.Union.Kubernetes resource
                )

        let {- if cert-manager is enabled, then includes and transforms the CertManager types
               into the new Union that combines Kubernetes and CertManager resources
            -} all-certificates =
                    if input.withCertManager

              then    Prelude.List.map
                        CertManager.Issuer.Type
                        CertManager.Union
                        CertManager.Union.Issuer
                        Components.CertManager.Issuers
                    # Prelude.List.map
                        CertManager.Certificate.Type
                        CertManager.Union
                        CertManager.Union.Certificate
                        Components.CertManager.Certificates

              else  [] : List CertManager.Union

        in  { Components = Components
            , List =
                { apiVersion = "v1"
                , kind = "List"
                , items =
                      all-certificates
                    # transformKubernetesResource
                        (   Prelude.List.map
                              Volume.Type
                              Kubernetes.Resource
                              mkSecret
                              (   zk-conf.ServiceVolumes
                                # [ etc-zuul, etc-nodepool, etc-zuul-registry ]
                              )
                          # mkUnion Components.Backend.Database
                          # mkUnion Components.Backend.ZooKeeper
                          # mkUnion Components.Zuul.Scheduler
                          # mkUnion Components.Zuul.Executor
                          # mkUnion Components.Zuul.Web
                          # mkUnion Components.Zuul.Merger
                          # mkUnion Components.Zuul.Registry
                          # mkUnion Components.Zuul.Preview
                          # mkUnion Components.Nodepool.Launcher
                        )
                }
            }
