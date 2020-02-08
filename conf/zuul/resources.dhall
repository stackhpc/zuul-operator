{- Zuul CR kubernetes resources

The evaluation of that file is a function that takes the cr inputs as an argument,
and returns the list of kubernetes of objects
-}
let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let Schemas = ./input.dhall

let Input = Schemas.Input.Type

let JobVolume = Schemas.JobVolume.Type

let UserSecret = Schemas.UserSecret.Type

let Label = { mapKey : Text, mapValue : Text }

let Labels = List Label

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

let DefaultText =
          \(value : Optional Text)
      ->  \(default : Text)
      ->  merge { None = default, Some = \(some : Text) -> some } value

let DefaultKey =
          \(secret : Optional UserSecret)
      ->  \(default : Text)
      ->  merge
            { None = default
            , Some = \(some : UserSecret) -> DefaultText some.key default
            }
            secret

let newlineSep = Prelude.Text.concatSep "\n"

let {- This methods process the optional input.job-volumes list. It takes:
    * the desired output type
    * a function that goes from JobVolume to the output type
    * the input.job-volumes spec attribute

    Then it returns a list of the output type
    -} mkJobVolume =
          \(OutputType : Type)
      ->  \(f : JobVolume -> OutputType)
      ->  \(job-volumes : Optional (List JobVolume))
      ->  merge
            { None = [] : List OutputType
            , Some = Prelude.List.map JobVolume OutputType f
            }
            job-volumes

let {- This method renders the zuul.conf
    -} mkZuulConf =
          \(input : Input)
      ->  \(zk-hosts : Text)
      ->  \(default-db-password : Text)
      ->  let {- This is a high level method. It takes:
              * a Connection type such as `Schemas.Gerrit.Type`,
              * an Optional List of that type
              * a function that goes from that type to a zuul.conf text blob

              Then it returns a text blob for all the connections
              -} mkConns =
                    \(type : Type)
                ->  \(list : Optional (List type))
                ->  \(f : type -> Text)
                ->  newlineSep
                      ( merge
                          { None = [] : List Text
                          , Some = Prelude.List.map type Text f
                          }
                          list
                      )

          let merger-email =
                DefaultText
                  input.merger.git_user_email
                  "${input.name}@localhost"

          let merger-user = DefaultText input.merger.git_user_name "Zuul"

          let executor-key-name =
                DefaultText input.executor.ssh_key.key "id_rsa"

          let sched-config = DefaultText input.scheduler.config.key "main.yaml"

          let web-url = DefaultText input.web.status_url "http://web:9000"

          let extra-kube-path = "/etc/nodepool-kubernetes/"

          let db-uri =
                merge
                  { None = "postgresql://zuul:${default-db-password}@db/zuul"
                  , Some = \(some : UserSecret) -> "%(ZUUL_DB_URI)"
                  }
                  input.database

          let gerrits-conf =
                mkConns
                  Schemas.Gerrit.Type
                  input.connections.gerrits
                  (     \(gerrit : Schemas.Gerrit.Type)
                    ->  let key = DefaultText gerrit.sshkey.key "id_rsa"

                        let server = DefaultText gerrit.server gerrit.name

                        in  ''
                            [connection ${gerrit.name}]
                            driver=gerrit
                            server=${server}
                            sshkey=/etc/zuul-gerrit-${gerrit.name}/${key}
                            user=${gerrit.user}
                            baseurl=${gerrit.baseurl}
                            ''
                  )

          let githubs-conf =
                mkConns
                  Schemas.GitHub.Type
                  input.connections.githubs
                  (     \(github : Schemas.GitHub.Type)
                    ->  let key = DefaultText github.app_key.key "github_rsa"

                        in  ''
                            [connection ${github.name}]
                            driver=github
                            server=github.com
                            app_id={github.app_id}
                            app_key=/etc/zuul-github-${github.name}/${key}
                            ''
                  )

          let gits-conf =
                mkConns
                  Schemas.Git.Type
                  input.connections.gits
                  (     \(git : Schemas.Git.Type)
                    ->  ''
                        [connection ${git.name}]
                        driver=git
                        baseurl=${git.baseurl}

                        ''
                  )

          let mqtts-conf =
                mkConns
                  Schemas.Mqtt.Type
                  input.connections.mqtts
                  (     \(mqtt : Schemas.Mqtt.Type)
                    ->  let user =
                              merge
                                { None = ""
                                , Some = \(some : Text) -> "user=${some}"
                                }
                                mqtt.user

                        let password =
                              merge
                                { None = ""
                                , Some =
                                        \(some : UserSecret)
                                    ->  "password=%(ZUUL_MQTT_PASSWORD)"
                                }
                                mqtt.password

                        in  ''
                            [connection ${mqtt.name}]
                            driver=mqtt
                            server=${mqtt.server}
                            ${user}
                            ${password}
                            ''
                  )

          let job-volumes =
                mkJobVolume
                  Text
                  (     \(job-volume : JobVolume)
                    ->  let {- TODO: add support for abritary lists of path per (context, access)
                            -} context =
                              merge
                                { trusted = "trusted", untrusted = "untrusted" }
                                job-volume.context

                        let access =
                              merge
                                { None = "ro"
                                , Some =
                                        \(access : < ro | rw >)
                                    ->  merge { ro = "ro", rw = "rw" } access
                                }
                                job-volume.access

                        in  "${context}_${access}_paths=${job-volume.path}"
                  )
                  input.job_volumes

          in      ''
                  [gearman]
                  server=scheduler
                  ssl_ca=/etc/zuul-gearman/ca.pem
                  ssl_cert=/etc/zuul-gearman/client.pem
                  ssl_key=/etc/zuul-gearman/client.key

                  [gearman_server]
                  start=true
                  ssl_ca=/etc/zuul-gearman/ca.pem
                  ssl_cert=/etc/zuul-gearman/server.pem
                  ssl_key=/etc/zuul-gearman/server.key

                  [zookeeper]
                  hosts=${zk-hosts}

                  [merger]
                  git_user_email=${merger-email}
                  git_user_name=${merger-user}

                  [scheduler]
                  tenant_config=/etc/zuul-scheduler/${sched-config}

                  [web]
                  listen_address=0.0.0.0
                  root=${web-url}

                  [executor]
                  private_key_file=/etc/zuul-executor/${executor-key-name}
                  manage_ansible=false

                  ''
              ++  Prelude.Text.concatSep "\n" job-volumes
              ++  ''

                  [connection "sql"]
                  driver=sql
                  dburi=${db-uri}

                  ''
              ++  gits-conf
              ++  gerrits-conf
              ++  githubs-conf
              ++  mqtts-conf

let mkNodepoolConf =
          \(zk-host : Text)
      ->  ''
          zookeeper-servers:
            - host: ${zk-host}
              port: 2181
          ''

in      \(input : Input)
    ->  let app-labels =
              [ { mapKey = "app.kubernetes.io/name", mapValue = input.name }
              , { mapKey = "app.kubernetes.io/instance", mapValue = input.name }
              , { mapKey = "app.kubernetes.io/part-of", mapValue = "zuul" }
              ]

        let component-label =
                  \(name : Text)
              ->    app-labels
                  # [ { mapKey = "app.kubernetes.io/component"
                      , mapValue = name
                      }
                    ]

        let mkObjectMeta =
                  \(name : Text)
              ->  \(labels : Labels)
              ->  Kubernetes.ObjectMeta::{ name = name, labels = Some labels }

        let mkSelector =
                  \(labels : Labels)
              ->  Kubernetes.LabelSelector::{ matchLabels = Some labels }

        let mkService =
                  \(name : Text)
              ->  \(port-name : Text)
              ->  \(port : Natural)
              ->  let labels = component-label name

                  in  Kubernetes.Service::{
                      , metadata = mkObjectMeta name labels
                      , spec = Some Kubernetes.ServiceSpec::{
                        , type = Some "ClusterIP"
                        , selector = Some labels
                        , ports = Some
                          [ Kubernetes.ServicePort::{
                            , name = Some port-name
                            , protocol = Some "TCP"
                            , targetPort = Some
                                (Kubernetes.IntOrString.String port-name)
                            , port = port
                            }
                          ]
                        }
                      }

        let mkVolumeEmptyDir =
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
              ->  \(labels : Labels)
              ->  Kubernetes.PodTemplateSpec::{
                  , metadata = mkObjectMeta component.name labels
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
              ->  let labels = component-label component.name

                  let component-name = input.name ++ "-" ++ component.name

                  let claim =
                              if Natural/isZero component.claim-size

                        then  [] : List Kubernetes.PersistentVolumeClaim.Type

                        else  [ Kubernetes.PersistentVolumeClaim::{
                                , apiVersion = ""
                                , kind = ""
                                , metadata =
                                    mkObjectMeta component-name ([] : Labels)
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
                      , metadata = mkObjectMeta component-name labels
                      , spec = Some Kubernetes.StatefulSetSpec::{
                        , serviceName = component.name
                        , replicas = Some component.count
                        , selector = mkSelector labels
                        , template = mkPodTemplateSpec component labels
                        , volumeClaimTemplates = Some claim
                        }
                      }

        let mkDeployment =
                  \(component : Component.Type)
              ->  let labels = component-label component.name

                  let component-name = input.name ++ "-" ++ component.name

                  in  Kubernetes.Deployment::{
                      , metadata = mkObjectMeta component-name labels
                      , spec = Some Kubernetes.DeploymentSpec::{
                        , replicas = Some component.count
                        , selector = mkSelector labels
                        , template = mkPodTemplateSpec component labels
                        }
                      }

        let mkEnvVarValue =
              Prelude.List.map
                Label
                Kubernetes.EnvVar.Type
                (     \(env : Label)
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

        let zk-hosts =
              merge
                { None = "zk"
                , Some = \(some : UserSecret) -> "%(ZUUL_ZK_HOSTS)"
                }
                input.zookeeper

        let zk-hosts-secret-env =
              merge
                { None = [] : List Kubernetes.EnvVar.Type
                , Some =
                        \(some : UserSecret)
                    ->  mkEnvVarSecret
                          [ { name = "ZUUL_ZK_HOSTS"
                            , secret = some.secretName
                            , key = DefaultText some.key "hosts"
                            }
                          ]
                }
                input.zookeeper

        let org = "docker.io/zuul"

        let version = "latest"

        let image = \(name : Text) -> "${org}/${name}:${version}"

        let etc-nodepool =
              Volume::{
              , name = input.name ++ "-secret-nodepool"
              , dir = "/etc/nodepool"
              , files =
                [ { path = "nodepool.yaml"
                  , content =
                      ''
                      zookeeper-servers:
                        - host: ${zk-hosts}
                          port: 2181
                      webapp:
                        port: 5000

                      ''
                  }
                ]
              }

        let {- TODO: generate random password -} default-db-password =
              "super-secret"

        let etc-zuul =
              Volume::{
              , name = input.name ++ "-secret-zuul"
              , dir = "/etc/zuul"
              , files =
                [ { path = "zuul.conf"
                  , content = mkZuulConf input zk-hosts default-db-password
                  }
                ]
              }

        let etc-nodepool =
              Volume::{
              , name = input.name ++ "-secret-nodepool"
              , dir = "/etc/nodepool"
              , files =
                [ { path = "nodepool.yaml", content = mkNodepoolConf zk-hosts }
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
                              , Service = Some (mkService "db" "pg" 5432)
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
                                            ( mkEnvVarValue
                                                ( toMap
                                                    { POSTGRES_USER = "zuul"
                                                    , POSTGRES_PASSWORD =
                                                        default-db-password
                                                    , PGDATA =
                                                        "/var/lib/pg/data"
                                                    }
                                                )
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
                              , Service = Some (mkService "zk" "zk" 2181)
                              , StatefulSet = Some
                                  ( mkStatefulSet
                                      Component::{
                                      , name = "zk"
                                      , count = 1
                                      , data-dir = zk-volumes
                                      , claim-size = 1
                                      , container = Kubernetes.Container::{
                                        , name = "zk"
                                        , image = Some
                                            "docker.io/library/zookeeper"
                                        , imagePullPolicy = Some "IfNotPresent"
                                        , ports = Some
                                          [ Kubernetes.ContainerPort::{
                                            , name = Some "zk"
                                            , containerPort = 2181
                                            }
                                          ]
                                        , volumeMounts = Some
                                            (mkVolumeMount zk-volumes)
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

                  let db-uri-secret-env =
                        merge
                          { None = [] : List Kubernetes.EnvVar.Type
                          , Some =
                                  \(some : UserSecret)
                              ->  mkEnvVarSecret
                                    [ { name = "ZUUL_DB_URI"
                                      , secret = some.secretName
                                      , key = DefaultText some.key "db_uri"
                                      }
                                    ]
                          }
                          input.database

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

                  let zuul-volumes = [ etc-zuul, gearman-config ]

                  let web-volumes = zuul-volumes

                  let merger-volumes = zuul-volumes

                  let scheduler-volumes = zuul-volumes # [ sched-config ]

                  let executor-volumes = zuul-volumes # [ executor-ssh-key ]

                  in  { Scheduler = KubernetesComponent::{
                        , Service = Some (mkService "scheduler" "gearman" 4730)
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
                                        # db-uri-secret-env
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
                        , Service = Some (mkService "executor" "finger" 7900)
                        , StatefulSet = Some
                            ( mkStatefulSet
                                Component::{
                                , name = "executor"
                                , count = 1
                                , data-dir = zuul-data-dir
                                , volumes = executor-volumes
                                , extra-volumes =
                                    let job-volumes =
                                          mkJobVolume
                                            Kubernetes.Volume.Type
                                            (     \(job-volume : JobVolume)
                                              ->  job-volume.volume
                                            )
                                            input.job_volumes

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
                                  , env = Some zuul-env
                                  , volumeMounts =
                                      let job-volumes-mount =
                                            mkJobVolume
                                              Volume.Type
                                              (     \(job-volume : JobVolume)
                                                ->  Volume::{
                                                    , name =
                                                        job-volume.volume.name
                                                    , dir = job-volume.dir
                                                    }
                                              )
                                              input.job_volumes

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
                        , Service = Some (mkService "web" "api" 9000)
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
                                  , env = Some zuul-env
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
                                  , env = Some zuul-env
                                  , volumeMounts = Some
                                      ( mkVolumeMount
                                          (merger-volumes # zuul-data-dir)
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
                          input.external_config.openstack

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
                          input.external_config.kubernetes

                  let nodepool-env =
                        mkEnvVarValue
                          ( toMap
                              { HOME = "/var/lib/nodepool"
                              , OS_CLIENT_CONFIG_FILE =
                                      "/etc/nodepool-openstack/"
                                  ++  DefaultKey
                                        input.external_config.openstack
                                        "clouds.yaml"
                              , KUBECONFIG =
                                      "/etc/nodepool-kubernetes/"
                                  ++  DefaultKey
                                        input.external_config.kubernetes
                                        "kube.config"
                              }
                          )

                  let nodepool-volumes =
                          [ etc-nodepool, nodepool-config ]
                        # openstack-config
                        # kubernetes-config

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
                      [ mkSecret etc-zuul, mkSecret etc-nodepool ]
                    # mkUnion Components.Backend.Database
                    # mkUnion Components.Backend.ZooKeeper
                    # mkUnion Components.Zuul.Scheduler
                    # mkUnion Components.Zuul.Executor
                    # mkUnion Components.Zuul.Web
                    # mkUnion Components.Zuul.Merger
                    # mkUnion Components.Nodepool.Launcher
                }
            }
