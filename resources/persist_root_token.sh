#!/bin/bash

echo $CLIENT_CERT | base64 -d > /tmp/cert.crt
echo $CLIENT_KEY | base64 -d > /tmp/cert.key
echo $CLUSTER_CA | base64 -d > /tmp/ca.crt

git clone https://github.com/czembower/utils.git
mv utils/curl-amd64 ./curl && chmod +x ./curl 

./curl -sLO https://storage.googleapis.com/kubernetes-release/release/$(./curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x ./kubectl

until [[ $(./kubectl exec --server $CLUSTER_ENDPOINT --client-certificate /tmp/cert.crt --client-key /tmp/cert.key --certificate-authority /tmp/ca.crt -i -n vault pod/primary-vault-0 -- stat /home/vault/init-output) ]]; do
    echo "waiting for vault service..."
    sleep 5
done

echo "init-output found"

token=""
until [[ $token ]]; do
    echo waiting for cluster initialization...
    sleep 5
    token=$(./kubectl exec --server $CLUSTER_ENDPOINT --client-certificate /tmp/cert.crt --client-key /tmp/cert.key --certificate-authority /tmp/ca.crt -i -n vault pod/primary-vault-0 -- cat /home/vault/init-output | grep Initial | awk -F ': ' {'print $2'})
done

if [[ "$token" == "s."* ]]; then
    echo "Found token: $token"
    echo "Creating k8s secret..."
    ./kubectl --server $CLUSTER_ENDPOINT --client-certificate /tmp/cert.crt --client-key /tmp/cert.key --certificate-authority /tmp/ca.crt create secret generic -n vault token --from-literal=token=$token
    echo "Done"
else
    echo "Error parsing token: $token"
    exit 1
fi
