# Hyperledger Fabric Helm Charts

This directory contains [Helm Charts](https://github.com/kubernetes/helm/blob/master/docs/charts.md) for creating an Hyperledger Fabric network developed in a sandbox.

## Setup your environment

### Kubernetes

Obtain a Kubernetes cluster and set `KUBECONFIG` to point to it.

```bash
export KUBECONFIG=<your kubernetes config file>
```

### Helm

1. Download and extract [Helm](https://github.com/kubernetes/helm#install) for your platform
2. Follow the instruction on how to set up help for your specific platform
3. Create a namespace where to install the network

    ```bash
    kubectl create namespace <namespace>
    ```

    **Note: If using any Kubernetes manager (e.g. Rancher), it is possible this command is enabled only via UI**

4. Initialise helm and upgrade the tiller if exists

    ```bash
    helm init [--tiller-namespace <namespace>] --upgrade
    ```

## Configurable and interactive setup (for PROD)

Complete setup with volumes attached to single components and data persistency

This setup includes:

- Data persistency for ledger (blockchain and state)

- Resources such as volumes, secrets and config are attached to single components (and not shared)

- Private keys, certificates and configuration files stored as secrets

- Configurations of environment variables stored as `ConfigMap`

- CA equipped with PostgreSQL/MySQL database for storing certificates

- Registration and enrollment of users is done dynamically

Deploy all the official charts by running the following commands:

```bash
./run.sh start -i
# or alternatively
./run.sh start prod
```

## Simple setup (for STAG)

Standard 2-orgs-1-peer not-extandable setup with one unique shared volume; no secrets; no data persistency

Deploy all the local charts by running the following commands:

```bash
./run.sh start
```

## Wipe all

Clean up the environment by running the following commands:

```bash
./run.sh clean <namespace>
```

## Run commands

This example is made for the `Production` extandable configuration, but can be easily changed to support the `Staging` one.

First, set some environment variables:

```bash
export namespaece=<k8s namespace where to set up the network>
export channel_name=<channel name id>
export chaincode_name=<chaincode name id>
export peer_address=<full address of the peer including port>
export orderer_address=<full address of the orderer including port>
export chaincode_path=<absolute pathname where your chaincode sits>
export chaincode_name=<partial pathname where your chaincode sits>
export chaincode_version=<initial version of the chaincode to deploy>
# e.g.
export namespaece="blockchain"
export channel_name="mychannel"
export chaincode_name="mychaincode"
export peer_address="org1peer1-hlf-peer:30110"
export orderer_address="orderer-hlf-ord:31010"
export chaincode_path="/home/me/stuff/go/cc"
export chaincode_name="cc"
export chaincode_version="1.0"
```

Copy the cloud/remote config, add to a file and export it as `KUBECONFIG` variable

```bash
export KUBECONFIG=<rancher configuration file>
```

Retrieve the CLI container name

```bash
cli_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-tools,release=cli" -o jsonpath="{.items[0].metadata.name}")
```

Now we are ready to start.

### Create and join channel

Generate the new channel configuration

```bash
./run.sh generate channeltx $channel_name ${PWD}/hlf ${PWD}/hlf/config ${PWD}/hlf/cryptos OneOrgOrdererGenesis OneOrgChannel Org1MSP
```

Add the channel configurations into a new secret

```bash
org_msp=<organisation id of the peer>
# e.g.
org_msp=Org1MSP
kubectl create secret generic --namespace $namespace hlf--${channel_name}-channel --from-file=${PWD}/hlf/channels/$channel_name/${channel_name}_tx.pb --from-file=${PWD}/hlf/channels/$channel_name/${org_msp}_anchors_tx.pb
```

Upgrade peer container adding the new secret

```bash
peer_name=<name assigned to the peer>
# e.g.
peer_name=org1peer1
helm upgrade --namespace $namespace --tiller-namespace $namespace --reuse-values --set secrets.channel=hlf--${channel_name}-channel $peer_name ./hlf/charts/hlf-peer
```

Retrieve the peer container name

```bash
peer_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-peer,release=${peer_name}" -o jsonpath="{.items[0].metadata.name}")
```

Create the channel through the peer

```bash
kubectl exec --namespace $namespace $peer_pod -- bash -c "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp peer channel create -o ${orderer_address} -c $channel_name -f /hl_config/channel/${channel_name}_tx.pb"
```

Fetch the channel block from the orderer

```bash
kubectl exec --namespace $namespace $peer_pod -- bash -c "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp peer channel fetch config /${channel_name}.block -c $channel_name -o ${orderer_address}"
```

Join the channel with the peer

```bash
kubectl exec --namespace $namespace $peer_pod -- bash -c "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp peer channel join -b /${channel_name}.block"
```

### Update a channel configuration

[Official tutorial](https://hyperledger-fabric.readthedocs.io/en/release-1.4/channel_update_tutorial.html)

```bash
kubectl exec --namespace $namespace $cli_pod -- bash -c "peer channel fetch config ${channel_name}.pb -c $channel_name -o $orderer_address
```

### Deploy chaincode

Copy chaincode codebase into peer container

```bash
kubectl cp --namespace $namespace $chaincode_path ${cli_pod}:/opt/gopath/src/chaincode/${chaincode_name}
```

#### Instantiate a new chaincode

Install chaincode

```bash
kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_address} peer chaincode install -n $chaincode_name -v $chaincode_version -p chaincode/${chaincode_name}"
# e.g.
```

Instantiate chaincode

```bash
kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_address} peer chaincode instantiate -o $orderer_address -n $chaincode_name -v $chaincode_version -C $channel_name -l <language of the chaincode> -c <args in json format> -P <endorsment policy>"
# e.g.
kubectl exec --namespace blockchain hlf-cli-pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=peer0:30110 peer chaincode instantiate -o orderer:31010 -n cc -v 1.0 -C mychannel -l golang -c '{\"Args\":[]}' -P \"OR('Org1MSP.member')\""
```

#### Upgrade a previous deployed chaincode

Install chaincode

```bash
chaincode_version=<a not-existing version of chaincode>
kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_address} peer chaincode install -n $chaincode_name -v $chaincode_version -p chaincode/${chaincode_name}"
# e.g.
kubectl exec --namespace blockchain hlf-cli-pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=peer0:30110 peer chaincode install -n cc -v 1.1 -p chaincode/cc"
```

Upgrade chaincode to new version

```bash
kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_address} peer chaincode upgrade -o $orderer_address -n $chaincode_name -v $chaincode_version -C $channel_name -l <language of the chaincode> -c <args in json format> -P <endorsment policy>"
# e.g.
kubectl exec --namespace blockchain hlf-cli-pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=peer0:30110 peer chaincode upgrade -o orderer:31010 -n cc -v 1.1 -C mychannel -l golang -c '{\"Args\":[]}' -P \"OR('Org1MSP.member')\""
```

### Run an invoke

```bash
kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=$peer_address peer chaincode invoke -o $orderer_address -C $channel_name -n $chaincode_name -c '{\"Args\":[\"put\",\"a\",\"10\"]}'"
```

### Run a query

```bash
kubectl exec --namespace blockchain $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=$peer_address peer chaincode invoke -o $orderer_adddress -C $channel_name -n $chaincode_name -c '{\"Args\":[\"get\",\"a\"]}'"
```

**Note: Chaincode cointainer is hidden, but the log get attached to the peer, so that you can see the output of your commands there.**

## Upgrading Hyperledger Fabric to a newer version (or reconfigure the service)

Copy and export the newer versions in environment variables:

```bash
export FABRIC_VERSION="1.4.1"
export THIRDPARTY_VERSION="0.4.15"
```

### CA

Updating the charts without resetting username and password:

Copy and export in environment variables `CA_ADMIN` and `CA_PASSWORD` and log them to be sure the command did work

```bash
export CA_ADMIN=$(kubectl get secret --namespace blockchain ca-hlf-ca--ca -o jsonpath="{.data.CA_ADMIN}" | base64 --decode; echo)
export CA_PASSWORD=$(kubectl get secret --namespace blockchain ca-hlf-ca--ca -o jsonpath="{.data.CA_PASSWORD}" | base64 --decode; echo)
echo $CA_ADMIN $CA_PASSWORD
```

Upgrade the chart

```bash
helm upgrade --namespace $namespace --tiller-namespace $namespace --reuse-values --set image.tag=$FABRIC_VERSION,config.hlfToolsVersion=$FABRIC_VERSION,postgresql.enabled=true,adminUsername=$CA_ADMIN,adminPassword=$CA_PASSWORD ca ./hlf/charts/hlf-ca
```

### Orderer

Upgrade the chart

```bash
helm upgrade  --namespace $namespace --tiller-namespace $namespace --reuse-values --set image.tag=$FABRIC_VERSION orderer ./hlf/charts/hlf-ord
```

### CouchDB

Copy and export CouchDB username and password

```bash
export COUCHDB_USERNAME=$(kubectl get secret --namespace blockchain cdb-org1peer1-hlf-couchdb -o jsonpath="{.data.COUCHDB_USERNAME}" | base64 --decode; echo)
export COUCHDB_PASSWORD=$(kubectl get secret --namespace blockchain cdb-org1peer1-hlf-couchdb -o jsonpath="{.data.COUCHDB_PASSWORD}" | base64 --decode; echo)
```

Update the chart without resetting the password (requires running step 2):

```bash
helm upgrade --namespace $namespace --tiller-namespace $namespace --reuse-values --set couchdbUsername=$COUCHDB_USERNAME,couchdbPassword=$COUCHDB_PASSWORD cdb-org1peer1 ./hlf/charts/hlf-couchdb
```

### Peer

Upgrade the chart

```bash
helm upgrade --namespace $namespace --tiller-namespace $namespace --reuse-values --set image.tag=$FABRIC_VERSION org1peer1 ./hlf/charts/hlf-peer
```

### CLI

Upgrading the chart

```bash
helm upgrade --namespace $namespace --tiller-namespace $namespace --reuse-values --set image.tag=$FABRIC_VERSION cli ./hlf/charts/hlf-tools
```

## References

[hlf-peer](https://github.com/helm/charts/tree/master/stable/hlf-peer)

[hlf-couchdb](https://github.com/helm/charts/tree/master/stable/hlf-couchdb)

[hlf-ca](https://github.com/helm/charts/tree/master/stable/hlf-ca)

[hlf-ord](https://github.com/helm/charts/tree/master/stable/hlf-ord)
