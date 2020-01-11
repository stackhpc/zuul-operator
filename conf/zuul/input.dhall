{- Zuul CR spec as a dhall schemas

> Note: in dhall, a record with such structure:
>  { Type = { foo : Text }, default = { foo = "bar" }}
> is named a `schemas` and it can be used to set default value:
> https://docs.dhall-lang.org/references/Built-in-types.html#id133


The `Schemas` record contains schemas for the CR spec attributes.

The `Input` record is the Zuul CR spec schema.
-}

let UserSecret = { secretName : Text, key : Optional Text }

let Gerrit =
      { name : Text
      , server : Optional Text
      , user : Text
      , baseurl : Text
      , sshkey : UserSecret
      }

let GitHub = { name : Text, app_id : Natural, app_key : UserSecret }

let Mqtt =
      { name : Text
      , server : Text
      , user : Optional Text
      , password : Optional UserSecret
      }

let Git = { name : Text, baseurl : Text }

let Schemas =
      { Merger =
          { Type =
              { image : Optional Text
              , count : Optional Natural
              , git_user_email : Optional Text
              , git_user_name : Optional Text
              }
          , default =
              { image = None Text
              , count = None Natural
              , git_user_email = None Text
              , git_user_name = None Text
              }
          }
      , Executor =
          { Type =
              { image : Optional Text
              , count : Optional Natural
              , ssh_key : UserSecret
              }
          , default = { image = None Text, count = None Natural }
          }
      , Web =
          { Type =
              { image : Optional Text
              , count : Optional Natural
              , status_url : Optional Text
              }
          , default =
              { image = None Text
              , count = None Natural
              , status_url = None Text
              }
          }
      , Scheduler =
          { Type =
              { image : Optional Text
              , count : Optional Natural
              , config : UserSecret
              }
          , default = { image = None Text, count = None Natural }
          }
      , Launcher =
          { Type = { image : Optional Text, config : UserSecret }
          , default = { image = None Text }
          }
      , Connections =
          { Type =
              { gerrits : Optional (List Gerrit)
              , githubs : Optional (List GitHub)
              , mqtts : Optional (List Mqtt)
              , gits : Optional (List Git)
              }
          , default =
              { gerrits = None (List Gerrit)
              , githubs = None (List GitHub)
              , mqtts = None (List Mqtt)
              , gits = None (List Git)
              }
          }
      , ExternalConfigs =
          { Type =
              { openstack : Optional UserSecret
              , kubernetes : Optional UserSecret
              , amazon : Optional UserSecret
              }
          , default =
              { openstack = None UserSecret
              , kubernetes = None UserSecret
              , amazon = None UserSecret
              }
          }
      , UserSecret = { Type = UserSecret, default = { key = None Text } }
      , Gerrit = { Type = Gerrit }
      , GitHub = { Type = GitHub }
      , Mqtt = { Type = Mqtt }
      , Git = { Type = Git }
      }

let Input =
      { Type =
          { name : Text
          , merger : Schemas.Merger.Type
          , executor : Schemas.Executor.Type
          , web : Schemas.Web.Type
          , scheduler : Schemas.Scheduler.Type
          , launcher : Schemas.Launcher.Type
          , database : Optional UserSecret
          , zookeeper : Optional UserSecret
          , external_config : Schemas.ExternalConfigs.Type
          , connections : Schemas.Connections.Type
          }
      , default =
          { database = None UserSecret
          , zookeeper = None UserSecret
          , external_config = Schemas.ExternalConfigs.default
          , merger = Schemas.Merger.default
          , web = Schemas.Web.default
          }
      }

in  Schemas // { Input = Input }
