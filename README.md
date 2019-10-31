# Deploying Hyperledger Fabric on a Kubernetes cluster

A collection of kubernetes configurations and helm charts used to deploy a blockchain network.

The current configuration of the network is set to:

- 2 organisations
- 2 peers (1 for each org)
- (optional) 2 couchdb state for the peers
- 1 ca
- 1 orderer (SOLO)

Therefore it is meant to be used mostly for development purposes.

## Prerequisites

- [Kubernetes](https://kubernetes.io/docs/setup/release/)
- [Helm](https://github.com/helm/helm)

## DEV: Using a single script

### Deployment

```bash
cd dev/scripts
./create_all [--with-couchdb]
```

### Cleanup

```bash
cd dev/scripts
./delete_all
```

### STAG and PROD: Using Helm charts

Follow the [README](helm/README.md)

## Troubleshooting

### Error in instantiating your chaincode. Your peer is logging

```bash
error trying to connect to local peer: userChaincodeStreamGetter -> ERRO 003 context deadline exceeded
```

> Broken communication between peer and chaincode. The reasons could be different:
>
> - `CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE="bridge"` is not set on the peer
>
> - `CORE_VM_ENDPOINT: “unix:///host/var/run/docker.sock”` is not set on the peer
>
> - `CORE_PEER_CHAINCODEADDRESS` is set with the wrong chaincode addres (**It is recommanded to comment this out**)

#### DeliveryBlocks error logged on the peer

```bash
[blocksProvider] DeliverBlocks -> ERRO 0b4 [mychannel] Got error &{FORBIDDEN}
```

> Check your orderer logs. There could be some broken communication with your peer.
> - The address of the orderer could be wrongly spelled in the `configtx.yaml` file or different from the one set on the peer
>
> - The admin user who is performing the operations of creating/joining the channel (CLI) is different from the one registered on the peer


#### Peer crashes immediately after launch

```bash
fatal error: unexpected signal during runtime execution
[signal SIGSEGV: segmentation violation code=0x1 addr=0x63 pc=0x7f9d15ded259]
runtime stack:
runtime.throw(0xdc37a7, 0x2a)
        /opt/go/src/runtime/panic.go:566 +0x95
runtime.sigpanic()
        /opt/go/src/runtime/sigpanic_unix.go:12 +0x2cc
goroutine 64 [syscall, locked to thread]:
runtime.cgocall(0xb08d50, 0xc4203bcdf8, 0xc400000000)
        /opt/go/src/runtime/cgocall.go:131 +0x110 fp=0xc4203bcdb0 sp=0xc4203bcd70
net._C2func_getaddrinfo(0x7f9d000008c0, 0x0, 0xc420323110, 0xc4201a01e8, 0x0, 0x0, 0x0)
```

> Be sure you to set `GODEBUG: “netdns=go”` on the peer
