let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

in      \(app-name : Text)
    ->  \(image-name : Optional Text)
    ->  \(data-dir : List F.Volume.Type)
    ->  \(volumes : List F.Volume.Type)
    ->  \(env : List Kubernetes.EnvVar.Type)
    ->  F.KubernetesComponent::{
        , Deployment = Some
            ( F.mkDeployment
                app-name
                F.Component::{
                , name = "merger"
                , count = 1
                , data-dir = data-dir
                , volumes = volumes
                , container = Kubernetes.Container::{
                  , name = "merger"
                  , image = image-name
                  , args = Some [ "zuul-merger", "-d" ]
                  , imagePullPolicy = Some "IfNotPresent"
                  , env = Some env
                  , volumeMounts = Some (F.mkVolumeMount (data-dir # volumes))
                  }
                }
            )
        }
