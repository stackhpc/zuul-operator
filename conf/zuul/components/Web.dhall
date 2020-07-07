let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

let InputWeb = (../input.dhall).Web.Type

in  \(app-name : Text) ->
    \(input-web : InputWeb) ->
    \(data-dir : List F.Volume.Type) ->
    \(volumes : List F.Volume.Type) ->
    \(env : List Kubernetes.EnvVar.Type) ->
      F.KubernetesComponent::{
      , Service = Some (F.mkService app-name "web" "api" 9000)
      , Deployment = Some
          ( F.mkDeployment
              app-name
              F.Component::{
              , name = "web"
              , count = 1
              , data-dir
              , volumes
              , container = Kubernetes.Container::{
                , name = "web"
                , image = input-web.image
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
