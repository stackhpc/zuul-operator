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

let EnvSecret = { name : Text, secret : Text, key : Text }

let File = { path : Text, content : Text }

let Volume =
      { Type = { name : Text, dir : Text, files : List File }
      , default.files = [] : List File
      }

let {- A high level description of a component such as the scheduler or the launcher
    -} Component =
      { Type =
          { name : Text
          , count : Natural
          , container : Kubernetes.Container.Type
          , data-dir : List Volume.Type
          , volumes : List Volume.Type
          , extra-volumes : List Kubernetes.Volume.Type
          , claim-size : Natural
          }
      , default =
          { data-dir = [] : List Volume.Type
          , volumes = [] : List Volume.Type
          , extra-volumes = [] : List Kubernetes.Volume.Type
          , claim-size = 0
          }
      }

let {- The Kubernetes resources of a Component
    -} KubernetesComponent =
      { Type =
          { Service : Optional Kubernetes.Service.Type
          , Deployment : Optional Kubernetes.Deployment.Type
          , StatefulSet : Optional Kubernetes.StatefulSet.Type
          }
      , default =
          { Service = None Kubernetes.Service.Type
          , Deployment = None Kubernetes.Deployment.Type
          , StatefulSet = None Kubernetes.StatefulSet.Type
          }
      }

in      \(input : Input)
    ->  let mkVolumeEmptyDir =
              Prelude.List.map
                Volume.Type
                Kubernetes.Volume.Type
                (     \(volume : Volume.Type)
                  ->  Kubernetes.Volume::{
                      , name = volume.name
                      , emptyDir = Some Kubernetes.EmptyDirVolumeSource::{=}
                      }
                )

        let mkVolumeSecret =
              Prelude.List.map
                Volume.Type
                Kubernetes.Volume.Type
                (     \(volume : Volume.Type)
                  ->  Kubernetes.Volume::{
                      , name = volume.name
                      , secret = Some Kubernetes.SecretVolumeSource::{
                        , secretName = Some volume.name
                        , defaultMode = Some 256
                        }
                      }
                )

        let mkPodTemplateSpec =
                  \(component : Component.Type)
              ->  \(labels : F.Labels)
              ->  Kubernetes.PodTemplateSpec::{
                  , metadata = F.mkObjectMeta component.name labels
                  , spec = Some Kubernetes.PodSpec::{
                    , volumes = Some
                        (   mkVolumeSecret component.volumes
                          # mkVolumeEmptyDir component.data-dir
                          # component.extra-volumes
                        )
                    , containers = [ component.container ]
                    , automountServiceAccountToken = Some False
                    }
                  }

        let mkStatefulSet =
                  \(component : Component.Type)
              ->  let labels = F.mkComponentLabel input.name component.name

                  let component-name = input.name ++ "-" ++ component.name

                  let claim =
                              if Natural/isZero component.claim-size

                        then  [] : List Kubernetes.PersistentVolumeClaim.Type

                        else  [ Kubernetes.PersistentVolumeClaim::{
                                , apiVersion = ""
                                , kind = ""
                                , metadata = Kubernetes.ObjectMeta::{
                                  , name = component-name
                                  }
                                , spec = Some Kubernetes.PersistentVolumeClaimSpec::{
                                  , accessModes = Some [ "ReadWriteOnce" ]
                                  , resources = Some Kubernetes.ResourceRequirements::{
                                    , requests = Some
                                        ( toMap
                                            { storage =
                                                    Natural/show
                                                      component.claim-size
                                                ++  "Gi"
                                            }
                                        )
                                    }
                                  }
                                }
                              ]

                  in  Kubernetes.StatefulSet::{
                      , metadata = F.mkObjectMeta component-name labels
                      , spec = Some Kubernetes.StatefulSetSpec::{
                        , serviceName = component.name
                        , replicas = Some component.count
                        , selector = F.mkSelector labels
                        , template = mkPodTemplateSpec component labels
                        , volumeClaimTemplates = Some claim
                        }
                      }

        let mkDeployment =
                  \(component : Component.Type)
              ->  let labels = F.mkComponentLabel input.name component.name

                  let component-name = input.name ++ "-" ++ component.name

                  in  Kubernetes.Deployment::{
                      , metadata = F.mkObjectMeta component-name labels
                      , spec = Some Kubernetes.DeploymentSpec::{
                        , replicas = Some component.count
                        , selector = F.mkSelector labels
                        , template = mkPodTemplateSpec component labels
                        }
                      }

        let mkEnvVarValue =
              Prelude.List.map
                F.Label
                Kubernetes.EnvVar.Type
                (     \(env : F.Label)
                  ->  Kubernetes.EnvVar::{
                      , name = env.mapKey
                      , value = Some env.mapValue
                      }
                )

        let mkEnvVarSecret =
              Prelude.List.map
                EnvSecret
                Kubernetes.EnvVar.Type
                (     \(env : EnvSecret)
                  ->  Kubernetes.EnvVar::{
                      , name = env.name
                      , valueFrom = Some Kubernetes.EnvVarSource::{
                        , secretKeyRef = Some Kubernetes.SecretKeySelector::{
                          , key = env.key
                          , name = Some env.secret
                          }
                        }
                      }
                )

        let mkVolumeMount =
              Prelude.List.map
                Volume.Type
                Kubernetes.VolumeMount.Type
                (     \(volume : Volume.Type)
                  ->  Kubernetes.VolumeMount::{
                      , name = volume.name
                      , mountPath = volume.dir
                      }
                )

        let mkSecret =
                  \(volume : Volume.Type)
              ->  Kubernetes.Resource.Secret
                    Kubernetes.Secret::{
                    , metadata = Kubernetes.ObjectMeta::{ name = volume.name }
                    , stringData = Some
                        ( Prelude.List.map
                            File
                            { mapKey : Text, mapValue : Text }
                            (     \(config : File)
                              ->  { mapKey = config.path
                                  , mapValue = config.content
                                  }
                            )
                            volume.files
                        )
                    }

        let zk-conf =
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
                    ->  mkEnvVarSecret
                          [ { name = "ZUUL_ZK_HOSTS"
                            , secret = some.secretName
                            , key = F.defaultText some.key "hosts"
                            }
                          ]
                }
                input.zookeeper

        let db-internal-password-env =
                  \(env-name : Text)
              ->  mkEnvVarSecret
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
                  let db-volumes =
                        [ Volume::{ name = "pg-data", dir = "/var/lib/pg/" } ]

                  let zk-volumes =
                        [ Volume::{
                          , name = "zk-log"
                          , dir = "/var/log/zookeeper/"
                          }
                        , Volume::{
                          , name = "zk-dat"
                          , dir = "/var/lib/zookeeper/"
                          }
                        ]

                  in  { Database =
                          merge
                            { None = KubernetesComponent::{
                              , Service = Some
                                  (F.mkService input.name "db" "pg" 5432)
                              , StatefulSet = Some
                                  ( mkStatefulSet
                                      Component::{
                                      , name = "db"
                                      , count = 1
                                      , data-dir = db-volumes
                                      , claim-size = 1
                                      , container = Kubernetes.Container::{
                                        , name = "db"
                                        , image = Some
                                            "docker.io/library/postgres:12.1"
                                        , imagePullPolicy = Some "IfNotPresent"
                                        , ports = Some
                                          [ Kubernetes.ContainerPort::{
                                            , name = Some "pg"
                                            , containerPort = 5432
                                            }
                                          ]
                                        , env = Some
                                            (   mkEnvVarValue
                                                  ( toMap
                                                      { POSTGRES_USER = "zuul"
                                                      , PGDATA =
                                                          "/var/lib/pg/data"
                                                      }
                                                  )
                                              # db-internal-password-env
                                                  "POSTGRES_PASSWORD"
                                            )
                                        , volumeMounts = Some
                                            (mkVolumeMount db-volumes)
                                        }
                                      }
                                  )
                              }
                            , Some =
                                    \(some : UserSecret)
                                ->  KubernetesComponent.default
                            }
                            input.database
                      , ZooKeeper =
                          merge
                            { None = KubernetesComponent::{
                              , Service = Some
                                  (F.mkService input.name "zk" "zk" 2281)
                              , StatefulSet = Some
                                  ( mkStatefulSet
                                      Component::{
                                      , name = "zk"
                                      , count = 1
                                      , data-dir = zk-volumes
                                      , volumes = zk-conf # zk-client-conf
                                      , claim-size = 1
                                      , container = Kubernetes.Container::{
                                        , name = "zk"
                                        , command = Some
                                          [ "sh"
                                          , "-c"
                                          ,     "cp /conf-tls/zoo.cfg /conf/ && "
                                            ++  "cp /etc/zookeeper-tls/zk.pem /conf/zk.pem && "
                                            ++  "cp /etc/zookeeper-tls/ca.crt /conf/ca.pem && "
                                            ++  "chown zookeeper /conf/zoo.cfg /conf/zk.pem /conf/ca.pem && "
                                            ++  "exec /docker-entrypoint.sh zkServer.sh start-foreground"
                                          ]
                                        , image = Some
                                            "docker.io/library/zookeeper"
                                        , imagePullPolicy = Some "IfNotPresent"
                                        , ports = Some
                                          [ Kubernetes.ContainerPort::{
                                            , name = Some "zk"
                                            , containerPort = 2281
                                            }
                                          ]
                                        , volumeMounts = Some
                                            ( mkVolumeMount
                                                (   zk-volumes
                                                  # zk-conf
                                                  # zk-client-conf
                                                )
                                            )
                                        }
                                      }
                                  )
                              }
                            , Some =
                                    \(some : UserSecret)
                                ->  KubernetesComponent.default
                            }
                            input.zookeeper
                      }
              , Zuul =
                  let zuul-image =
                        \(name : Text) -> Some (image ("zuul-" ++ name))

                  let zuul-env =
                        mkEnvVarValue (toMap { HOME = "/var/lib/zuul" })

                  let db-secret-env =
                        merge
                          { None = db-internal-password-env "ZUUL_DB_PASSWORD"
                          , Some =
                                  \(some : UserSecret)
                              ->  mkEnvVarSecret
                                    [ { name = "ZUUL_DB_URI"
                                      , secret = some.secretName
                                      , key = F.defaultText some.key "db_uri"
                                      }
                                    ]
                          }
                          input.database

                  let {- executor and merger do not need database info, but they fail to parse config without the env variable
                      -} db-nosecret-env =
                        mkEnvVarValue (toMap { ZUUL_DB_PASSWORD = "unused" })

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

                  in  { Scheduler = KubernetesComponent::{
                        , Service = Some
                            (F.mkService input.name "scheduler" "gearman" 4730)
                        , StatefulSet = Some
                            ( mkStatefulSet
                                Component::{
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
                                      ( mkVolumeMount
                                          (scheduler-volumes # zuul-data-dir)
                                      )
                                  }
                                }
                            )
                        }
                      , Executor = KubernetesComponent::{
                        , Service = Some
                            (F.mkService input.name "executor" "finger" 7900)
                        , StatefulSet = Some
                            ( mkStatefulSet
                                Component::{
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
                                            ( mkVolumeMount
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
                      , Web = KubernetesComponent::{
                        , Service = Some
                            (F.mkService input.name "web" "api" 9000)
                        , Deployment = Some
                            ( mkDeployment
                                Component::{
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
                                      ( mkVolumeMount
                                          (web-volumes # zuul-data-dir)
                                      )
                                  }
                                }
                            )
                        }
                      , Merger = KubernetesComponent::{
                        , Deployment = Some
                            ( mkDeployment
                                Component::{
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
                                      ( mkVolumeMount
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
                                mkEnvVarSecret
                                  ( Prelude.List.map
                                      Text
                                      EnvSecret
                                      (     \(key : Text)
                                        ->  { name = "ZUUL_REGISTRY_${key}"
                                            , key = key
                                            , secret =
                                                input.name ++ "-registry-tls"
                                            }
                                      )
                                      [ "secret", "username", "password" ]
                                  )

                          in  KubernetesComponent::{
                              , Service = Some
                                  ( F.mkService
                                      input.name
                                      "registry"
                                      "registry"
                                      9000
                                  )
                              , StatefulSet = Some
                                  ( mkStatefulSet
                                      Component::{
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
                                            ( mkVolumeMount
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
                        mkEnvVarValue
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

                  in  { Launcher = KubernetesComponent::{
                        , Deployment = Some
                            ( mkDeployment
                                Component::{
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
                                      ( mkVolumeMount
                                          (nodepool-volumes # nodepool-data-dir)
                                      )
                                  }
                                }
                            )
                        }
                      }
              }

        let {- This function transforms the different types into the Kubernetes.Resource
               union to enable using them inside a single List array
            -} mkUnion =
                  \(component : KubernetesComponent.Type)
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
