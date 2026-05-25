kubectl patch deployment zuul-web --patch-file=patch-files/web-key-patchfile.yaml
kubectl patch statefulset zuul-scheduler  --patch-file=patch-files/scheduler-key-patchfile.yaml
kubectl patch service zuul-web  --patch-file=patch-files/web-service-patchfile.yaml
kubectl patch statefulset zuul-executor  --patch-file=patch-files/executor-key-patchfile.yaml
kubectl patch statefulset zookeeper --patch-file=patch-files/zookeeper-image-patchfile.yaml
