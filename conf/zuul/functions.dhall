{- Common functions -}
let Prelude = ../Prelude.dhall

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

in  { defaultNat = defaultNat
    , defaultText = defaultText
    , defaultKey = defaultKey
    , newlineSep = Prelude.Text.concatSep "\n"
    , mkJobVolume = mkJobVolume
    }
