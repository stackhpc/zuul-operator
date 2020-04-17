let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

let InputPreview = (../input.dhall).Preview.Type

in      \(app-name : Text)
    ->  \(input-preview : InputPreview)
    ->  \(data-dir : List F.Volume.Type)
    ->  F.KubernetesComponent::{
        , Service = Some (F.mkService app-name "preview" "preview" 80)
        , Deployment = Some
            ( F.mkDeployment
                app-name
                F.Component::{
                , name = "preview"
                , count = F.defaultNat input-preview.count 0
                , data-dir = data-dir
                , container = Kubernetes.Container::{
                  , name = "preview"
                  , image = input-preview.image
                  , imagePullPolicy = Some "IfNotPresent"
                  , ports = Some
                    [ Kubernetes.ContainerPort::{
                      , name = Some "preview"
                      , containerPort = 80
                      }
                    ]
                  , env = Some
                    [ Kubernetes.EnvVar::{
                      , name = "ZUUL_API_URL"
                      , value = Some "http://web:9000"
                      }
                    ]
                  , volumeMounts = Some (F.mkVolumeMount data-dir)
                  }
                }
            )
        }
