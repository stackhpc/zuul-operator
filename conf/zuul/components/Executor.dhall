let Kubernetes = ../../Kubernetes.dhall

let F = ../functions.dhall

let JobVolume = (../input.dhall).JobVolume.Type

in      \(app-name : Text)
    ->  \(image-name : Optional Text)
    ->  \(data-dir : List F.Volume.Type)
    ->  \(volumes : List F.Volume.Type)
    ->  \(env : List Kubernetes.EnvVar.Type)
    ->  \(jobVolumes : Optional (List JobVolume))
    ->  F.KubernetesComponent::{
        , Service = Some (F.mkService app-name "executor" "finger" 7900)
        , StatefulSet = Some
            ( F.mkStatefulSet
                app-name
                F.Component::{
                , name = "executor"
                , count = 1
                , data-dir = data-dir
                , volumes = volumes
                , extra-volumes =
                    let job-volumes =
                          F.mkJobVolume
                            Kubernetes.Volume.Type
                            (\(job-volume : JobVolume) -> job-volume.volume)
                            jobVolumes

                    in  job-volumes
                , claim-size = 0
                , container = Kubernetes.Container::{
                  , name = "executor"
                  , image = image-name
                  , args = Some [ "zuul-executor", "-d" ]
                  , imagePullPolicy = Some "IfNotPresent"
                  , ports = Some
                    [ Kubernetes.ContainerPort::{
                      , name = Some "finger"
                      , containerPort = 7900
                      }
                    ]
                  , env = Some env
                  , volumeMounts =
                      let job-volumes-mount =
                            F.mkJobVolume
                              F.Volume.Type
                              (     \(job-volume : JobVolume)
                                ->  F.Volume::{
                                    , name = job-volume.volume.name
                                    , dir = job-volume.dir
                                    }
                              )
                              jobVolumes

                      in  Some
                            ( F.mkVolumeMount
                                (data-dir # volumes # job-volumes-mount)
                            )
                  , securityContext = Some Kubernetes.SecurityContext::{
                    , privileged = Some True
                    }
                  }
                }
            )
        }
