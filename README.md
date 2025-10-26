
Briefly to install homelab:

```
1. find -name "*.template"
2. "setup all integrations and put secrets found *.template files"
3. cd ansible/install-k3s
4. bash install.sh
5. cp ~/.kube/config{-homelab,} ~/.kube/config
6. cd ../install-restrictive-proxy
7. bash install.sh
8. cd ../..
9. kubectl apply -f integrations.yaml
10. cd helmfile
11. helmfile sync
```

For full details see https://homelab.zengarden.space
