{- Common functions -}
let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let JobVolume = (./input.dhall).JobVolume.Type

let UserSecret = (./input.dhall).UserSecret.Type

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

in  { defaultNat = defaultNat
    , defaultText = defaultText
    , defaultKey = defaultKey
    , newlineSep = Prelude.Text.concatSep "\n"
    , mkJobVolume = mkJobVolume
    , mkComponentLabel = mkComponentLabel
    , mkObjectMeta = mkObjectMeta
    , mkSelector = mkSelector
    , mkService = mkService
    , Label = Label
    , Labels = Labels
    }
