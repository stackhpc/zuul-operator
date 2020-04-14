let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

in      \(app-name : Text)
    ->  \(image-name : Optional Text)
    ->  \(data-dir : List F.Volume.Type)
    ->  \(volumes : List F.Volume.Type)
    ->  \(env : List Kubernetes.EnvVar.Type)
    ->  F.KubernetesComponent::{
        , Service = Some (F.mkService app-name "web" "api" 9000)
        , Deployment = Some
            ( F.mkDeployment
                app-name
                F.Component::{
                , name = "web"
                , count = 1
                , data-dir = data-dir
                , volumes = volumes
                , container = Kubernetes.Container::{
                  , name = "web"
                  , image = image-name
                  , args = Some [ "zuul-web", "-d" ]
                  , imagePullPolicy = Some "IfNotPresent"
                  , ports = Some
                    [ Kubernetes.ContainerPort::{
                      , name = Some "api"
                      , containerPort = 9000
                      }
                    ]
                  , env = Some env
                  , volumeMounts = Some (F.mkVolumeMount (data-dir # volumes))
                  }
                }
            )
        }
