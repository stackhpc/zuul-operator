{- This function converts a client-dir and server-dir Text to a zoo.cfg file content
-}
\(client-dir : Text) ->
\(server-dir : Text) ->
  ''
  dataDir=/data
  dataLogDir=/datalog
  tickTime=2000
  initLimit=5
  syncLimit=2
  autopurge.snapRetainCount=3
  autopurge.purgeInterval=0
  maxClientCnxns=60
  standaloneEnabled=true
  admin.enableServer=true
  server.1=0.0.0.0:2888:3888

  # TLS configuration
  secureClientPort=2281
  serverCnxnFactory=org.apache.zookeeper.server.NettyServerCnxnFactory
  ssl.keyStore.location=${server-dir}/zk.pem
  ssl.trustStore.location=${client-dir}/ca.pem
  ''
