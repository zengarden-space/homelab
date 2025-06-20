#!/bin/bash

set -euo pipefail

export KUBECONFIG=`pwd`/kubeconfig

pushd /var/run/secrets/kubernetes.io/serviceaccount

NAMESPACE=$(cat namespace)
TOKEN=$(cat token)
CACERT=`pwd`/ca.crt
APISERVER=https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}

popd

kubectl config set-cluster cluster --server=$APISERVER --certificate-authority=$CACERT --embed-certs=true
kubectl config set-credentials user --token=$TOKEN
kubectl config set-context context --cluster=cluster --user=user --namespace=$NAMESPACE
kubectl config use-context context

CERT=$(kubectl get secret ca-root-tls -o json | jq '.data["tls.crt"]' -r)
EXPIRATION_DATE=$(echo $CERT | base64 -d | openssl x509 -noout -enddate | awk -F '=' '{print $2}' | date +%y%d%m%H%M%S -f -)

kubectl apply -f - <<DOC
apiVersion: v1
kind: Secret
metadata:
  name: ca-root-tls-$EXPIRATION_DATE
  labels:
    belongs: ca-root
data:
  ca.crt: $CERT
DOC

echo -n > ca.crt

for SECRET in `kubectl get secret -o name -l belongs=ca-root`; do
  kubectl get $SECRET -o json | jq '.data["ca.crt"]' -r | base64 -d > one.crt
  echo -n "$SECRET expiration: "
  if cat one.crt | openssl x509 -noout -checkend 0; then
    cat one.crt >> ca.crt
  else
    kubectl delete $SECRET
  fi
done

echo "Trust roots PEM:"
cat ca.crt

kubectl apply -f - <<DOC
apiVersion: v1
kind: ConfigMap
metadata:
  name: internal-ca-tls
data:
  ca.crt: |
$(cat ca.crt | sed 's/^/    /')
DOC
