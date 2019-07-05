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
3. Initialise helm and upgrade the tiller if exists

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
./deploy.sh start -i
# or alternatively
./deploy.sh start prod
```

## Simple setup (for STAG)

Standard 2-orgs-1-peer not-extandable setup with one unique shared volume; no secrets; no data persistency

Deploy all the local charts by running the following commands:

```bash
./deploy_charts.sh start
```

## Wipe all

Clean up the environment by running the following commands:

```bash
./deploy_charts.sh clean <namespace>
```

## Run commands

This example is made for the `Production` extandable configuration, but can be easily changed to support the `Staging` one.

1. Set some environment variables

    ```bash
    export namespaece=<k8s namespace where to set up the network>
    export channel_name=<channel name id>
    export chaincode_name=<chaincode name id>
    export peer_address=<full address of the peer including port>
    export orderer_address=<full address of the orderer including port>

    # e.g.
    export namespaece="blockchain"
    export channel_name="mychannel"
    export chaincode_name="mychaincode"
    export peer_address="org1peer1-hlf-peer:30110"
    export orderer_address="orderer-hlf-ord:31010"
    ```

2. Copy the cloud/remote config, add to a file and export it as `KUBECONFIG` variable

    ```bash
    export KUBECONFIG=<rancher configuration file>
    ```

3. Retrieve the CLI container name

    ```bash
    cli_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-tools,release=cli" -o jsonpath="{.items[0].metadata.name}")
    ```

4. Run an invoke:

    ```bash
    kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=$peer_address peer chaincode invoke -o $orderer_address -C $channel_name -n $chaincode_name -c '{\"Args\":[\"put\",\"a\",\"10\"]}'"
    ```

5. Run a query:

    ```bash
    kubectl exec --namespace blockchain $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=$peer_address peer chaincode invoke -o $orderer_adddress -C $channel_name -n $chaincode_name -c '{\"Args\":[\"get\",\"a\"]}'"
    ```

**Note: Chaincode cointainer is hidden, but the log get attached to the peer, so that you can see the output of your commands there.**

### Deploy a new chaincode

1. Set some environment variables before starting

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

2. Copy the cloud/remote config, add to a file and export it as `KUBECONFIG` variable

    ```bash
    export KUBECONFIG=<rancher configuration file>
    ```

3. Copy chaincode codebase into peer container

    ```bash
    kubectl cp --namespace $namespace $chaincode_path ${cli_pod}:/opt/gopath/src/chaincode/${chaincode_path} 1>/dev/null
    ```

4. Install chaincode

    ```bash
    kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_address} peer chaincode install -n $chaincode_name -v $chaincode_version -p chaincode/${chaincode_name}"

    # e.g.
    kubectl exec --namespace blockchain hlf-cli-pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=peer0:30110 peer chaincode install -n cc -v 1.0 -p chaincode/cc"
    ```

5. Instantiate chaincode

    ```bash
    kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_address} peer chaincode instantiate -o $orderer_address -n $chaincode_name -v $chaincode_version -C $channel_name -l <language of the chaincode> -c <args in json format> -P <endorsment policy>"

    # e.g.
    kubectl exec --namespace blockchain hlf-cli-pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=peer0:30110 peer chaincode instantiate -o orderer:31010 -n cc -v 1.0 -C mychannel -l golang -c '{\"Args\":[]}' -P \"OR('Org1MSP.member')\""
    ```

## References

[hlf-peer](https://github.com/helm/charts/tree/master/stable/hlf-peer)

[hlf-couchdb](https://github.com/helm/charts/tree/master/stable/hlf-couchdb)

[hlf-ca](https://github.com/helm/charts/tree/master/stable/hlf-ca)

[hlf-ord](https://github.com/helm/charts/tree/master/stable/hlf-ord)