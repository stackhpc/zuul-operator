{- A local cert manager package that extends the Kubernetes binding

TODO: Use union combinaison once it is available, see https://github.com/dhall-lang/dhall-lang/issues/175
TODO: Check with the dhall kubernetes community if the new type could be contributed,
      though it currently only covers what is needed for zuul.
-}

let Kubernetes = ./Kubernetes.dhall

let IssuerSpec =
      { Type = { selfSigned : Optional {}, ca : Optional { secretName : Text } }
      , default = { selfSigned = None {}, ca = None { secretName : Text } }
      }

let Issuer =
      { Type =
          { apiVersion : Text
          , kind : Text
          , metadata : Kubernetes.ObjectMeta.Type
          , spec : IssuerSpec.Type
          }
      , default = { apiVersion = "cert-manager.io/v1alpha2", kind = "Issuer" }
      }

let CertificateSpec =
      { Type =
          { secretName : Text
          , isCA : Optional Bool
          , usages : Optional (List Text)
          , commonName : Optional Text
          , dnsNames : Optional (List Text)
          , issuerRef : { name : Text, kind : Text, group : Text }
          }
      , default =
        { isCA = None Bool
        , usages = None (List Text)
        , commonName = None Text
        , dnsNames = None (List Text)
        }
      }

let Certificate =
      { Type =
          { apiVersion : Text
          , kind : Text
          , metadata : Kubernetes.ObjectMeta.Type
          , spec : CertificateSpec.Type
          }
      , default =
        { apiVersion = "cert-manager.io/v1alpha3", kind = "Certificate" }
      }

let Union =
      < Kubernetes : Kubernetes.Resource
      | Issuer : Issuer.Type
      | Certificate : Certificate.Type
      >

in  { IssuerSpec, Issuer, CertificateSpec, Certificate, Union }
