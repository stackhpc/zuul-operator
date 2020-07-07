{- This function converts a public-url Text to a registry.yaml file content

-}
\(public-url : Text) ->
  ''
  registry:
    address: '0.0.0.0'
    port: 9000
    public-url: ${public-url}
    tls-cert: /etc/zuul-registry/tls.crt
    tls-key: /etc/zuul-registry/tls.key
    secret: "%(ZUUL_REGISTRY_secret)"
    storage:
      driver: filesystem
      root: /var/lib/zuul
    users:
      - name: "%(ZUUL_REGISTRY_username)"
        pass: "%(ZUUL_REGISTRY_password)"
        access: write
  ''
