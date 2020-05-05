{- Zuul CR kubernetes resources

The evaluation of that file is a function that takes the cr inputs as an argument,
and returns the list of kubernetes of objects.

The resources expect secrets to be created by the zuul ansible role:

* `${name}-gearman-tls` with:
  * `ca.pem`
  * `server.pem`
  * `server.key`
  * `client.pem`
  * `client.key`

* `${name}-zookeeper-tls` with:
  * `ca.crt`
  * `tls.crt`
  * `tls.key`
  * `zk.pem` the keystore

* `${name}-registry-tls` with:
  * `cert.pem`
  * `cert.key`
  * `secret` a password
  * `username` the user name with write access
  * `password` the user password

* `${name}-database-password` with a `password` key, (unless an input.database db uri is provided).
-}
let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

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
                , Some = \(some : UserSecret) -> [] : List Volume.Type
                }
                input.zookeeper

        let zk-client-conf =
              merge
                { None =
                  [ Volume::{
                    , name = "${input.name}-zookeeper-tls"
                    , dir = "/etc/zookeeper-tls"
                    }
                  ]
                , Some = \(some : UserSecret) -> [] : List Volume.Type
                }
                input.zookeeper

        let zk-hosts-zuul =
              merge
                { None =
                    ''
                    hosts=zk:2281
                    tls_cert=/etc/zookeeper-tls/tls.crt
                    tls_key=/etc/zookeeper-tls/tls.key
                    tls_ca=/etc/zookeeper-tls/ca.crt
                    ''
                , Some = \(some : UserSecret) -> "hosts=%(ZUUL_ZK_HOSTS)"
                }
                input.zookeeper

        let zk-hosts-nodepool =
              merge
                { None =
                    ''
                    zookeeper-servers:
                      - host: zk
                        port: 2281
                    zookeeper-tls:
                        cert: /etc/zookeeper-tls/tls.crt
                        key: /etc/zookeeper-tls/tls.key
                        ca: /etc/zookeeper-tls/ca.crt
                    ''
                , Some =
                        \(some : UserSecret)
                    ->  ''
                        zookeeper-servers:
                          - hosts: %(ZUUL_ZK_HOSTS)"
                        ''
                }
                input.zookeeper

        let {- Add support for TLS protected external zookeeper service
            -} zk-hosts-secret-env =
              merge
                { None = [] : List Kubernetes.EnvVar.Type
                , Some =
                        \(some : UserSecret)
                    ->  F.mkEnvVarSecret
                          [ { name = "ZUUL_ZK_HOSTS"
                            , secret = some.secretName
                            , key = F.defaultText some.key "hosts"
                            }
                          ]
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

        let org = "docker.io/zuul"

        let version = "latest"

        let image = \(name : Text) -> "${org}/${name}:${version}"

        let etc-zuul =
              Volume::{
              , name = input.name ++ "-secret-zuul"
              , dir = "/etc/zuul"
              , files =
                [ { path = "zuul.conf"
                  , content = ./files/zuul.conf.dhall input zk-hosts-zuul
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
                  , content = ./files/nodepool.yaml.dhall zk-hosts-nodepool
                  }
                ]
              }

        let Components =
              { Backend =
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
                              (zk-client-conf # zk-conf)
                        , Some =
                                \(some : UserSecret)
                            ->  F.KubernetesComponent.default
                        }
                        input.zookeeper
                  }
              , Zuul =
                  let zuul-image =
                        \(name : Text) -> Some (image ("zuul-" ++ name))

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
                        [ etc-zuul, gearman-config ] # zk-client-conf

                  let web-volumes = zuul-volumes

                  let merger-volumes = zuul-volumes

                  let scheduler-volumes = zuul-volumes # [ sched-config ]

                  let executor-volumes = zuul-volumes # [ executor-ssh-key ]

                  in  { Scheduler = F.KubernetesComponent::{
                        , Service = Some
                            (F.mkService input.name "scheduler" "gearman" 4730)
                        , StatefulSet = Some
                            ( F.mkStatefulSet
                                input.name
                                F.Component::{
                                , name = "scheduler"
                                , count = 1
                                , data-dir = zuul-data-dir
                                , volumes = scheduler-volumes
                                , claim-size = 5
                                , container = Kubernetes.Container::{
                                  , name = "scheduler"
                                  , image = zuul-image "scheduler"
                                  , args = Some [ "zuul-scheduler", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , ports = Some
                                    [ Kubernetes.ContainerPort::{
                                      , name = Some "gearman"
                                      , containerPort = 4730
                                      }
                                    ]
                                  , env = Some
                                      (   zuul-env
                                        # db-secret-env
                                        # zk-hosts-secret-env
                                      )
                                  , volumeMounts = Some
                                      ( F.mkVolumeMount
                                          (scheduler-volumes # zuul-data-dir)
                                      )
                                  }
                                }
                            )
                        }
                      , Executor = F.KubernetesComponent::{
                        , Service = Some
                            (F.mkService input.name "executor" "finger" 7900)
                        , StatefulSet = Some
                            ( F.mkStatefulSet
                                input.name
                                F.Component::{
                                , name = "executor"
                                , count = 1
                                , data-dir = zuul-data-dir
                                , volumes = executor-volumes
                                , extra-volumes =
                                    let job-volumes =
                                          F.mkJobVolume
                                            Kubernetes.Volume.Type
                                            (     \(job-volume : JobVolume)
                                              ->  job-volume.volume
                                            )
                                            input.jobVolumes

                                    in  job-volumes
                                , claim-size = 0
                                , container = Kubernetes.Container::{
                                  , name = "executor"
                                  , image = zuul-image "executor"
                                  , args = Some [ "zuul-executor", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , ports = Some
                                    [ Kubernetes.ContainerPort::{
                                      , name = Some "finger"
                                      , containerPort = 7900
                                      }
                                    ]
                                  , env = Some (zuul-env # db-nosecret-env)
                                  , volumeMounts =
                                      let job-volumes-mount =
                                            F.mkJobVolume
                                              Volume.Type
                                              (     \(job-volume : JobVolume)
                                                ->  Volume::{
                                                    , name =
                                                        job-volume.volume.name
                                                    , dir = job-volume.dir
                                                    }
                                              )
                                              input.jobVolumes

                                      in  Some
                                            ( F.mkVolumeMount
                                                (   executor-volumes
                                                  # zuul-data-dir
                                                  # job-volumes-mount
                                                )
                                            )
                                  , securityContext = Some Kubernetes.SecurityContext::{
                                    , privileged = Some True
                                    }
                                  }
                                }
                            )
                        }
                      , Web = F.KubernetesComponent::{
                        , Service = Some
                            (F.mkService input.name "web" "api" 9000)
                        , Deployment = Some
                            ( F.mkDeployment
                                input.name
                                F.Component::{
                                , name = "web"
                                , count = 1
                                , data-dir = zuul-data-dir
                                , volumes = web-volumes
                                , container = Kubernetes.Container::{
                                  , name = "web"
                                  , image = zuul-image "web"
                                  , args = Some [ "zuul-web", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , ports = Some
                                    [ Kubernetes.ContainerPort::{
                                      , name = Some "api"
                                      , containerPort = 9000
                                      }
                                    ]
                                  , env = Some
                                      (   zuul-env
                                        # db-secret-env
                                        # zk-hosts-secret-env
                                      )
                                  , volumeMounts = Some
                                      ( F.mkVolumeMount
                                          (web-volumes # zuul-data-dir)
                                      )
                                  }
                                }
                            )
                        }
                      , Merger = F.KubernetesComponent::{
                        , Deployment = Some
                            ( F.mkDeployment
                                input.name
                                F.Component::{
                                , name = "merger"
                                , count = 1
                                , data-dir = zuul-data-dir
                                , volumes = merger-volumes
                                , container = Kubernetes.Container::{
                                  , name = "merger"
                                  , image = zuul-image "merger"
                                  , args = Some [ "zuul-merger", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , env = Some (zuul-env # db-nosecret-env)
                                  , volumeMounts = Some
                                      ( F.mkVolumeMount
                                          (merger-volumes # zuul-data-dir)
                                      )
                                  }
                                }
                            )
                        }
                      , Registry =
                          let registry-volumes =
                                [ etc-zuul-registry
                                , Volume::{
                                  , name = input.name ++ "-registry-tls"
                                  , dir = "/etc/zuul-registry"
                                  }
                                ]

                          let registry-env =
                                F.mkEnvVarSecret
                                  ( Prelude.List.map
                                      Text
                                      F.EnvSecret
                                      (     \(key : Text)
                                        ->  { name = "ZUUL_REGISTRY_${key}"
                                            , key = key
                                            , secret =
                                                input.name ++ "-registry-tls"
                                            }
                                      )
                                      [ "secret", "username", "password" ]
                                  )

                          in  F.KubernetesComponent::{
                              , Service = Some
                                  ( F.mkService
                                      input.name
                                      "registry"
                                      "registry"
                                      9000
                                  )
                              , StatefulSet = Some
                                  ( F.mkStatefulSet
                                      input.name
                                      F.Component::{
                                      , name = "registry"
                                      , count =
                                          F.defaultNat input.registry.count 0
                                      , data-dir = zuul-data-dir
                                      , volumes = registry-volumes
                                      , claim-size =
                                          F.defaultNat
                                            input.registry.storage-size
                                            20
                                      , container = Kubernetes.Container::{
                                        , name = "registry"
                                        , image = zuul-image "registry"
                                        , args = Some
                                          [ "zuul-registry"
                                          , "-c"
                                          , "/etc/zuul/registry.yaml"
                                          , "serve"
                                          ]
                                        , imagePullPolicy = Some "IfNotPresent"
                                        , ports = Some
                                          [ Kubernetes.ContainerPort::{
                                            , name = Some "registry"
                                            , containerPort = 9000
                                            }
                                          ]
                                        , env = Some registry-env
                                        , volumeMounts = Some
                                            ( F.mkVolumeMount
                                                (   registry-volumes
                                                  # zuul-data-dir
                                                )
                                            )
                                        }
                                      }
                                  )
                              }
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
                        # zk-client-conf

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

        in  { Components = Components
            , List =
                { apiVersion = "v1"
                , kind = "List"
                , items =
                      Prelude.List.map
                        Volume.Type
                        Kubernetes.Resource
                        mkSecret
                        (   zk-conf
                          # [ etc-zuul, etc-nodepool, etc-zuul-registry ]
                        )
                    # mkUnion Components.Backend.Database
                    # mkUnion Components.Backend.ZooKeeper
                    # mkUnion Components.Zuul.Scheduler
                    # mkUnion Components.Zuul.Executor
                    # mkUnion Components.Zuul.Web
                    # mkUnion Components.Zuul.Merger
                    # mkUnion Components.Zuul.Registry
                    # mkUnion Components.Nodepool.Launcher
                }
            }
