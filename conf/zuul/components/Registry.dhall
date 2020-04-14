let Prelude = ../../Prelude.dhall

let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

let InputRegistry = (../input.dhall).Registry.Type

let registry-volumes =
          \(app-name : Text)
      ->  [ F.Volume::{
            , name = app-name ++ "-registry-tls"
            , dir = "/etc/zuul-registry"
            }
          ]

let registry-env =
          \(app-name : Text)
      ->  F.mkEnvVarSecret
            ( Prelude.List.map
                Text
                F.EnvSecret
                (     \(key : Text)
                  ->  { name = "ZUUL_REGISTRY_${key}"
                      , key = key
                      , secret = app-name ++ "-registry-tls"
                      }
                )
                [ "secret", "username", "password" ]
            )

in      \(app-name : Text)
    ->  \(image-name : Optional Text)
    ->  \(data-dir : List F.Volume.Type)
    ->  \(volumes : List F.Volume.Type)
    ->  \(input-registry : InputRegistry)
    ->  F.KubernetesComponent::{
        , Service = Some (F.mkService app-name "registry" "registry" 9000)
        , StatefulSet = Some
            ( F.mkStatefulSet
                app-name
                F.Component::{
                , name = "registry"
                , count = F.defaultNat input-registry.count 0
                , data-dir = data-dir
                , volumes = volumes # registry-volumes app-name
                , claim-size = F.defaultNat input-registry.storage-size 20
                , container = Kubernetes.Container::{
                  , name = "registry"
                  , image = image-name
                  , args = Some
                    [ "zuul-registry"
                    , "-c"
                    , "/etc/zuul/registry.yaml"
                    , "serve"
                    ]
                  , imagePullPolicy = Some "IfNotPresent"
                  , ports = Some
                    [ Kubernetes.ContainerPort::{
                      , name = Some "registry"
                      , containerPort = 9000
                      }
                    ]
                  , env = Some (registry-env app-name)
                  , volumeMounts = Some
                      ( F.mkVolumeMount
                          (data-dir # volumes # registry-volumes app-name)
                      )
                  }
                }
            )
        }
