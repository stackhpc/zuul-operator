let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

let InputMerger = (../input.dhall).Merger.Type

in  \(app-name : Text) ->
    \(input-merger : InputMerger) ->
    \(data-dir : List F.Volume.Type) ->
    \(volumes : List F.Volume.Type) ->
    \(env : List Kubernetes.EnvVar.Type) ->
      F.KubernetesComponent::{
      , Deployment = Some
          ( F.mkDeployment
              app-name
              F.Component::{
              , name = "merger"
              , count = 1
              , data-dir
              , volumes
              , container = Kubernetes.Container::{
                , name = "merger"
                , image = input-merger.image
                , args = Some [ "zuul-merger", "-d" ]
                , imagePullPolicy = Some "IfNotPresent"
                , env = Some env
                , volumeMounts = Some (F.mkVolumeMount (data-dir # volumes))
                }
              }
          )
      }
