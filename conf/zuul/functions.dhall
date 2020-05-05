{- Common functions -}
let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let Schemas = ./input.dhall

let JobVolume = Schemas.JobVolume.Type

let UserSecret = Schemas.UserSecret.Type

let {- This methods process the optional input.job-volumes list. It takes:
    * the desired output type
    * a function that goes from JobVolume to the output type
    * the input.job-volumes spec attribute

    Then it returns a list of the output type
    -} mkJobVolume =
          \(OutputType : Type)
      ->  \(f : JobVolume -> OutputType)
      ->  \(job-volumes : Optional (List JobVolume))
      ->  merge
            { None = [] : List OutputType
            , Some = Prelude.List.map JobVolume OutputType f
            }
            job-volumes

let defaultNat =
          \(value : Optional Natural)
      ->  \(default : Natural)
      ->  merge { None = default, Some = \(some : Natural) -> some } value

let defaultText =
          \(value : Optional Text)
      ->  \(default : Text)
      ->  merge { None = default, Some = \(some : Text) -> some } value

let defaultKey =
          \(secret : Optional UserSecret)
      ->  \(default : Text)
      ->  merge
            { None = default
            , Some = \(some : UserSecret) -> defaultText some.key default
            }
            secret

let mkAppLabels =
          \(app-name : Text)
      ->  [ { mapKey = "app.kubernetes.io/name", mapValue = app-name }
          , { mapKey = "app.kubernetes.io/instance", mapValue = app-name }
          , { mapKey = "app.kubernetes.io/part-of", mapValue = "zuul" }
          ]

let mkComponentLabel =
          \(app-name : Text)
      ->  \(component-name : Text)
      ->    mkAppLabels app-name
          # [ { mapKey = "app.kubernetes.io/component"
              , mapValue = component-name
              }
            ]

let Label = { mapKey : Text, mapValue : Text }

let Labels = List Label

let mkObjectMeta =
          \(name : Text)
      ->  \(labels : Labels)
      ->  Kubernetes.ObjectMeta::{ name = name, labels = Some labels }

let mkSelector =
          \(labels : Labels)
      ->  Kubernetes.LabelSelector::{ matchLabels = Some labels }

let mkService =
          \(app-name : Text)
      ->  \(name : Text)
      ->  \(port-name : Text)
      ->  \(port : Natural)
      ->  let labels = mkComponentLabel app-name name

          in  Kubernetes.Service::{
              , metadata = mkObjectMeta name labels
              , spec = Some Kubernetes.ServiceSpec::{
                , type = Some "ClusterIP"
                , selector = Some labels
                , ports = Some
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

let EnvSecret = { name : Text, secret : Text, key : Text }

let File = { path : Text, content : Text }

let Volume =
      { Type = { name : Text, dir : Text, files : List File }
      , default.files = [] : List File
      }

let {- A high level description of a component such as the scheduler or the launcher
    -} Component =
      { Type =
          { name : Text
          , count : Natural
          , container : Kubernetes.Container.Type
          , data-dir : List Volume.Type
          , volumes : List Volume.Type
          , extra-volumes : List Kubernetes.Volume.Type
          , claim-size : Natural
          }
      , default =
          { data-dir = [] : List Volume.Type
          , volumes = [] : List Volume.Type
          , extra-volumes = [] : List Kubernetes.Volume.Type
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

let mkVolumeEmptyDir =
      Prelude.List.map
        Volume.Type
        Kubernetes.Volume.Type
        (     \(volume : Volume.Type)
          ->  Kubernetes.Volume::{
              , name = volume.name
              , emptyDir = Some Kubernetes.EmptyDirVolumeSource::{=}
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
                , defaultMode = Some 256
                }
              }
        )

let mkPodTemplateSpec =
          \(component : Component.Type)
      ->  \(labels : Labels)
      ->  Kubernetes.PodTemplateSpec::{
          , metadata = mkObjectMeta component.name labels
          , spec = Some Kubernetes.PodSpec::{
            , volumes = Some
                (   mkVolumeSecret component.volumes
                  # mkVolumeEmptyDir component.data-dir
                  # component.extra-volumes
                )
            , containers = [ component.container ]
            , automountServiceAccountToken = Some False
            }
          }

let mkStatefulSet =
          \(app-name : Text)
      ->  \(component : Component.Type)
      ->  let labels = mkComponentLabel app-name component.name

          let component-name = app-name ++ "-" ++ component.name

          let claim =
                      if Natural/isZero component.claim-size

                then  [] : List Kubernetes.PersistentVolumeClaim.Type

                else  [ Kubernetes.PersistentVolumeClaim::{
                        , apiVersion = ""
                        , kind = ""
                        , metadata = Kubernetes.ObjectMeta::{
                          , name = component-name
                          }
                        , spec = Some Kubernetes.PersistentVolumeClaimSpec::{
                          , accessModes = Some [ "ReadWriteOnce" ]
                          , resources = Some Kubernetes.ResourceRequirements::{
                            , requests = Some
                                ( toMap
                                    { storage =
                                            Natural/show component.claim-size
                                        ++  "Gi"
                                    }
                                )
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
                , volumeClaimTemplates = Some claim
                }
              }

let mkDeployment =
          \(app-name : Text)
      ->  \(component : Component.Type)
      ->  let labels = mkComponentLabel app-name component.name

          let component-name = app-name ++ "-" ++ component.name

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
              , valueFrom = Some Kubernetes.EnvVarSource::{
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

in  { defaultNat = defaultNat
    , defaultText = defaultText
    , defaultKey = defaultKey
    , newlineSep = Prelude.Text.concatSep "\n"
    , mkJobVolume = mkJobVolume
    , mkComponentLabel = mkComponentLabel
    , mkObjectMeta = mkObjectMeta
    , mkSelector = mkSelector
    , mkService = mkService
    , mkDeployment = mkDeployment
    , mkStatefulSet = mkStatefulSet
    , mkVolumeMount = mkVolumeMount
    , mkEnvVarValue = mkEnvVarValue
    , mkEnvVarSecret = mkEnvVarSecret
    , EnvSecret = EnvSecret
    , Label = Label
    , Labels = Labels
    , Volume = Volume
    , Component = Component
    , KubernetesComponent = KubernetesComponent
    }
