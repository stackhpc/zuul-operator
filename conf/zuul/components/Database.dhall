let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

let db-volumes = [ F.Volume::{ name = "pg-data", dir = "/var/lib/pg/" } ]

in  \(app-name : Text) ->
    \ ( db-internal-password-env
      : forall (env-name : Text) -> List Kubernetes.EnvVar.Type
      ) ->
      F.KubernetesComponent::{
      , Service = Some (F.mkService app-name "db" "pg" 5432)
      , StatefulSet = Some
          ( F.mkStatefulSet
              app-name
              F.Component::{
              , name = "db"
              , count = 1
              , data-dir = db-volumes
              , claim-size = 1
              , container = Kubernetes.Container::{
                , name = "db"
                , image = Some "docker.io/library/postgres:12.1"
                , imagePullPolicy = Some "IfNotPresent"
                , ports = Some
                  [ Kubernetes.ContainerPort::{
                    , name = Some "pg"
                    , containerPort = 5432
                    }
                  ]
                , env = Some
                    (   F.mkEnvVarValue
                          ( toMap
                              { POSTGRES_USER = "zuul"
                              , PGDATA = "/var/lib/pg/data"
                              }
                          )
                      # db-internal-password-env "POSTGRES_PASSWORD"
                    )
                , volumeMounts = Some (F.mkVolumeMount db-volumes)
                }
              }
          )
      }
