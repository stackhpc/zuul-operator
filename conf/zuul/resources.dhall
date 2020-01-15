{- Zuul CR kubernetes resources

The evaluation of that file is a function that takes the cr inputs as an argument,
and returns the list of kubernetes of objects
-}
let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let Schemas = ./input.dhall

let Input = Schemas.Input.Type

let UserSecret = Schemas.UserSecret.Type

let Label = { mapKey : Text, mapValue : Text }

let Labels = List Label

let EnvSecret = { name : Text, secret : Text, key : Text }

let File = { path : Text, content : Text }

let Volume =
      { Type = { name : Text, dir : Text, files : List File }
      , default = { files = [] : List File }
      }

let {- A high level description of a component such as the scheduler or the launcher
    -} Component =
      { Type =
          { name : Text
          , count : Natural
          , container : Kubernetes.Container.Type
          , data-dir : List Volume.Type
          , volumes : List Volume.Type
          , claim-size : Natural
          }
      , default =
          { data-dir = [] : List Volume.Type
          , volumes = [] : List Volume.Type
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
      ->  Optional/fold Text value Text (\(some : Text) -> some) default

let DefaultKey =
          \(secret : Optional UserSecret)
      ->  \(default : Text)
      ->  Optional/fold
            UserSecret
            secret
            Text
            (\(some : UserSecret) -> DefaultText some.key default)
            default

let newlineSep = Prelude.Text.concatSep "\n"

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
                      ( Optional/fold
                          (List type)
                          list
                          (List Text)
                          (Prelude.List.map type Text f)
                          ([] : List Text)
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
                Optional/fold
                  UserSecret
                  input.database
                  Text
                  (\(some : UserSecret) -> "%(ZUUL_DB_URI)")
                  "postgresql://zuul:${default-db-password}@db/zuul"

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
                              Optional/fold
                                Text
                                mqtt.user
                                Text
                                (\(some : Text) -> "user=${some}")
                                ""

                        let password =
                              Optional/fold
                                UserSecret
                                mqtt.password
                                Text
                                (     \(password : UserSecret)
                                  ->  "password=%(ZUUL_MQTT_PASSWORD)"
                                )
                                ""

                        in  ''
                            [connection ${mqtt.name}]
                            driver=mqtt
                            server=${mqtt.server}
                            ${user}
                            ${password}
                            ''
                  )

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

                  [connection "sql"]
                  driver=sql
                  dburi=${db-uri}

                  ''
              ++  gits-conf
              ++  gerrits-conf
              ++  githubs-conf
              ++  mqtts-conf

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
              ->  Kubernetes.ObjectMeta::{ name = name, labels = labels }

        let mkSelector =
                  \(labels : Labels)
              ->  Kubernetes.LabelSelector::{ matchLabels = labels }

        let mkService =
                  \(name : Text)
              ->  \(port-name : Text)
              ->  \(port : Natural)
              ->  let labels = component-label name

                  in  Kubernetes.Service::{
                      , metadata = mkObjectMeta name labels
                      , spec = Some Kubernetes.ServiceSpec::{
                        , type = Some "ClusterIP"
                        , selector = labels
                        , ports =
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
                      , emptyDir = Kubernetes.EmptyDirVolumeSource::{
                        , medium = Some ""
                        }
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
                        }
                      }
                )

        let mkPodTemplateSpec =
                  \(component : Component.Type)
              ->  \(labels : Labels)
              ->  Kubernetes.PodTemplateSpec::{
                  , metadata = mkObjectMeta component.name labels
                  , spec = Some Kubernetes.PodSpec::{
                    , volumes =
                          mkVolumeSecret component.volumes
                        # mkVolumeEmptyDir component.data-dir
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
                                  , accessModes = [ "ReadWriteOnce" ]
                                  , resources = Some Kubernetes.ResourceRequirements::{
                                    , requests =
                                        toMap
                                          { storage =
                                                  Natural/show
                                                    component.claim-size
                                              ++  "Gi"
                                          }
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
                        , volumeClaimTemplates = claim
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
                      , valueFrom = Kubernetes.EnvVarSource::{
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
                    , stringData =
                        Prelude.List.map
                          File
                          { mapKey : Text, mapValue : Text }
                          (     \(config : File)
                            ->  { mapKey = config.path
                                , mapValue = config.content
                                }
                          )
                          volume.files
                    }

        let zk-hosts =
              Optional/fold
                UserSecret
                input.zookeeper
                Text
                (\(some : UserSecret) -> "%(ZUUL_ZK_HOSTS)")
                "zk"

        let zk-hosts-secret-env =
              Optional/fold
                UserSecret
                input.zookeeper
                (List Kubernetes.EnvVar.Type)
                (     \(some : UserSecret)
                  ->  mkEnvVarSecret
                        [ { name = "ZUUL_ZK_HOSTS"
                          , secret = some.secretName
                          , key = DefaultText some.key "hosts"
                          }
                        ]
                )
                ([] : List Kubernetes.EnvVar.Type)

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
                          Optional/fold
                            UserSecret
                            input.database
                            KubernetesComponent.Type
                            (     \(some : UserSecret)
                              ->  KubernetesComponent.default
                            )
                            KubernetesComponent::{
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
                                      , ports =
                                        [ Kubernetes.ContainerPort::{
                                          , name = Some "pg"
                                          , containerPort = 5432
                                          }
                                        ]
                                      , env =
                                          mkEnvVarValue
                                            ( toMap
                                                { POSTGRES_USER = "zuul"
                                                , POSTGRES_PASSWORD =
                                                    default-db-password
                                                , PGDATA = "/var/lib/pg/data"
                                                }
                                            )
                                      , volumeMounts = mkVolumeMount db-volumes
                                      }
                                    }
                                )
                            }
                      , ZooKeeper =
                          Optional/fold
                            UserSecret
                            input.zookeeper
                            KubernetesComponent.Type
                            (     \(some : UserSecret)
                              ->  KubernetesComponent.default
                            )
                            KubernetesComponent::{
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
                                      , ports =
                                        [ Kubernetes.ContainerPort::{
                                          , name = Some "zk"
                                          , containerPort = 2181
                                          }
                                        ]
                                      , volumeMounts = mkVolumeMount zk-volumes
                                      }
                                    }
                                )
                            }
                      }
              , Zuul =
                  let zuul-image =
                        \(name : Text) -> Some (image ("zuul-" ++ name))

                  let zuul-env =
                        mkEnvVarValue (toMap { HOME = "/var/lib/zuul" })

                  let db-uri-secret-env =
                        Optional/fold
                          UserSecret
                          input.database
                          (List Kubernetes.EnvVar.Type)
                          (     \(some : UserSecret)
                            ->  mkEnvVarSecret
                                  [ { name = "ZUUL_DB_URI"
                                    , secret = some.secretName
                                    , key = DefaultText some.key "db_uri"
                                    }
                                  ]
                          )
                          ([] : List Kubernetes.EnvVar.Type)

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

                  let conn-keys = [ gearman-config ]

                  let web-volumes = [ etc-zuul ]

                  let merger-volumes = [ etc-zuul ]

                  let scheduler-volumes = [ etc-zuul, sched-config ] # conn-keys

                  let executor-volumes =
                        [ etc-zuul, executor-ssh-key ] # conn-keys

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
                                  , args = [ "zuul-scheduler", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , ports =
                                    [ Kubernetes.ContainerPort::{
                                      , name = Some "gearman"
                                      , containerPort = 4730
                                      }
                                    ]
                                  , env =
                                        zuul-env
                                      # db-uri-secret-env
                                      # zk-hosts-secret-env
                                  , volumeMounts =
                                      mkVolumeMount
                                        (scheduler-volumes # zuul-data-dir)
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
                                , claim-size = 0
                                , container = Kubernetes.Container::{
                                  , name = "executor"
                                  , image = zuul-image "executor"
                                  , args = [ "zuul-executor", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , ports =
                                    [ Kubernetes.ContainerPort::{
                                      , name = Some "finger"
                                      , containerPort = 7900
                                      }
                                    ]
                                  , env = zuul-env
                                  , volumeMounts =
                                      mkVolumeMount
                                        (executor-volumes # zuul-data-dir)
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
                                  , args = [ "zuul-web", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , ports =
                                    [ Kubernetes.ContainerPort::{
                                      , name = Some "api"
                                      , containerPort = 9000
                                      }
                                    ]
                                  , env = zuul-env
                                  , volumeMounts =
                                      mkVolumeMount
                                        (web-volumes # zuul-data-dir)
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
                                  , args = [ "zuul-merger", "-d" ]
                                  , imagePullPolicy = Some "IfNotPresent"
                                  , env = zuul-env
                                  , volumeMounts =
                                      mkVolumeMount
                                        (merger-volumes # zuul-data-dir)
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

                  in    Optional/fold
                          Kubernetes.Service.Type
                          component.Service
                          (List Kubernetes.Resource)
                          (     \(some : Kubernetes.Service.Type)
                            ->  [ Kubernetes.Resource.Service some ]
                          )
                          empty
                      # Optional/fold
                          Kubernetes.StatefulSet.Type
                          component.StatefulSet
                          (List Kubernetes.Resource)
                          (     \(some : Kubernetes.StatefulSet.Type)
                            ->  [ Kubernetes.Resource.StatefulSet some ]
                          )
                          empty
                      # Optional/fold
                          Kubernetes.Deployment.Type
                          component.Deployment
                          (List Kubernetes.Resource)
                          (     \(some : Kubernetes.Deployment.Type)
                            ->  [ Kubernetes.Resource.Deployment some ]
                          )
                          empty

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
                }
            }
