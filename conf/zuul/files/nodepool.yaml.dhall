{- This function converts a zk-host Text to a nodepool.yaml file content

TODO: replace opaque Text by structured zk host list and tls configuration
-}
\(zk-host : Text) ->
  ''
  ${zk-host}

  webapp:
    port: 5000
  ''
