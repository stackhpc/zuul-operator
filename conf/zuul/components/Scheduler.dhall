let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

in      \(app-name : Text)
    ->  \(image-name : Optional Text)
    ->  \(data-dir : List F.Volume.Type)
    ->  \(volumes : List F.Volume.Type)
    ->  \(env : List Kubernetes.EnvVar.Type)
    ->  F.KubernetesComponent::{
        , Service = Some (F.mkService app-name "scheduler" "gearman" 4730)
        , StatefulSet = Some
            ( F.mkStatefulSet
                app-name
                F.Component::{
                , name = "scheduler"
                , count = 1
                , data-dir = data-dir
                , volumes = volumes
                , claim-size = 5
                , container = Kubernetes.Container::{
                  , name = "scheduler"
                  , image = image-name
                  , args = Some [ "zuul-scheduler", "-d" ]
                  , imagePullPolicy = Some "IfNotPresent"
                  , ports = Some
                    [ Kubernetes.ContainerPort::{
                      , name = Some "gearman"
                      , containerPort = 4730
                      }
                    ]
                  , env = Some env
                  , volumeMounts = Some (F.mkVolumeMount (data-dir # volumes))
                  }
                }
            )
        }
