{- This method renders the zuul.conf.

TODO: replace input schemas by the required attributes.
-}

    \(input : (../input.dhall).Input.Type)
->  \(zk-hosts : Text)
->  let Prelude = ../../Prelude.dhall

    let Schemas = ../input.dhall

    let F = ../functions.dhall

    let {- This is a high level method. It takes:
        * a Connection type such as `Schemas.Gerrit.Type`,
        * an Optional List of that type
        * a function that goes from that type to a zuul.conf text blob

        Then it returns a text blob for all the connections
        -} mkConns =
              \(type : Type)
          ->  \(list : Optional (List type))
          ->  \(f : type -> Text)
          ->  F.newlineSep
                ( merge
                    { None = [] : List Text
                    , Some = Prelude.List.map type Text f
                    }
                    list
                )

    let merger-email =
          F.defaultText input.merger.git_user_email "${input.name}@localhost"

    let merger-user = F.defaultText input.merger.git_user_name "Zuul"

    let executor-key-name = F.defaultText input.executor.ssh_key.key "id_rsa"

    let sched-config = F.defaultText input.scheduler.config.key "main.yaml"

    let web-url = F.defaultText input.web.status_url "http://web:9000"

    let extra-kube-path = "/etc/nodepool-kubernetes/"

    let db-uri =
          merge
            { None = "postgresql://zuul:%(ZUUL_DB_PASSWORD)s@db/zuul"
            , Some = \(some : Schemas.UserSecret.Type) -> "%(ZUUL_DB_URI)s"
            }
            input.database

    let gerrits-conf =
          mkConns
            Schemas.Gerrit.Type
            input.connections.gerrits
            (     \(gerrit : Schemas.Gerrit.Type)
              ->  let key = F.defaultText gerrit.sshkey.key "id_rsa"

                  let server = F.defaultText gerrit.server gerrit.name

                  in  ''
                      [connection ${gerrit.name}]
                      driver=gerrit
                      server=${server}
                      sshkey=/etc/zuul-gerrit-${gerrit.name}/${key}
                      user=${gerrit.user}
                      baseurl=${gerrit.baseurl}
                      ''
            )

    let githubs-conf =
          mkConns
            Schemas.GitHub.Type
            input.connections.githubs
            (     \(github : Schemas.GitHub.Type)
              ->  let key = F.defaultText github.app_key.key "github_rsa"

                  in  ''
                      [connection ${github.name}]
                      driver=github
                      server=github.com
                      app_id={github.app_id}
                      app_key=/etc/zuul-github-${github.name}/${key}
                      ''
            )

    let gits-conf =
          mkConns
            Schemas.Git.Type
            input.connections.gits
            (     \(git : Schemas.Git.Type)
              ->  ''
                  [connection ${git.name}]
                  driver=git
                  baseurl=${git.baseurl}

                  ''
            )

    let mqtts-conf =
          mkConns
            Schemas.Mqtt.Type
            input.connections.mqtts
            (     \(mqtt : Schemas.Mqtt.Type)
              ->  let user =
                        merge
                          { None = "", Some = \(some : Text) -> "user=${some}" }
                          mqtt.user

                  let password =
                        merge
                          { None = ""
                          , Some =
                                  \(some : Schemas.UserSecret.Type)
                              ->  "password=%(ZUUL_MQTT_PASSWORD)"
                          }
                          mqtt.password

                  in  ''
                      [connection ${mqtt.name}]
                      driver=mqtt
                      server=${mqtt.server}
                      ${user}
                      ${password}
                      ''
            )

    let job-volumes =
          F.mkJobVolume
            Text
            (     \(job-volume : Schemas.JobVolume.Type)
              ->  let {- TODO: add support for abritary lists of path per (context, access)
                      -} context =
                        merge
                          { trusted = "trusted", untrusted = "untrusted" }
                          job-volume.context

                  let access =
                        merge
                          { None = "ro"
                          , Some =
                                  \(access : < ro | rw >)
                              ->  merge { ro = "ro", rw = "rw" } access
                          }
                          job-volume.access

                  in  "${context}_${access}_paths=${job-volume.path}"
            )
            input.jobVolumes

    in      ''
            [gearman]
            server=scheduler
            ssl_ca=/etc/zuul-gearman/ca.pem
            ssl_cert=/etc/zuul-gearman/client.pem
            ssl_key=/etc/zuul-gearman/client.key

            [gearman_server]
            start=true
            ssl_ca=/etc/zuul-gearman/ca.pem
            ssl_cert=/etc/zuul-gearman/server.pem
            ssl_key=/etc/zuul-gearman/server.key

            [zookeeper]
            ${zk-hosts}

            [merger]
            git_user_email=${merger-email}
            git_user_name=${merger-user}

            [scheduler]
            tenant_config=/etc/zuul-scheduler/${sched-config}

            [web]
            listen_address=0.0.0.0
            root=${web-url}

            [executor]
            private_key_file=/etc/zuul-executor/${executor-key-name}
            manage_ansible=false

            ''
        ++  Prelude.Text.concatSep "\n" job-volumes
        ++  ''

            [connection "sql"]
            driver=sql
            dburi=${db-uri}

            ''
        ++  gits-conf
        ++  gerrits-conf
        ++  githubs-conf
        ++  mqtts-conf
