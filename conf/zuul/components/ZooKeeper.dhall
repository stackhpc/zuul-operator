{- This function returns the ZooKeeper component in case the user doesn't provide it's own service.
   The volumes list should contains the zoo
-}
let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

let data-volumes =
      [ F.Volume::{ name = "zk-log", dir = "/var/log/zookeeper/" }
      , F.Volume::{ name = "zk-dat", dir = "/var/lib/zookeeper/" }
      ]

in  \(app-name : Text) ->
    \(client-conf : List F.Volume.Type) ->
      F.KubernetesComponent::{
      , Service = Some (F.mkService app-name "zk" "zk" 2281)
      , StatefulSet = Some
          ( F.mkStatefulSet
              app-name
              F.Component::{
              , name = "zk"
              , count = 1
              , data-dir = data-volumes
              , volumes = client-conf
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
                , image = Some "docker.io/library/zookeeper"
                , imagePullPolicy = Some "IfNotPresent"
                , ports = Some
                  [ Kubernetes.ContainerPort::{
                    , name = Some "zk"
                    , containerPort = 2281
                    }
                  ]
                , volumeMounts = Some
                    (F.mkVolumeMount (data-volumes # client-conf))
                }
              }
          )
      }
