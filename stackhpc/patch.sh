kubectl patch deployment zuul-web --patch-file=patch-files/key-patchfile.yaml
kubectl patch service zuul-web  --patch-file=patch-files/web-service-patchfile.yaml
