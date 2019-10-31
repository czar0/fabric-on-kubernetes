#!/bin/bash

export FABRIC_VERSION=1.4.2
export THIRDPARTY_VERSION=0.4.15

#
# check_dependecies: Checks to ensure required tools are installed.
#
 check_dependecies() {
    type kubectl >/dev/null 2>&1 || { echo >&2 "I require kubectl but it is not installed.  Aborting."; exit 1; }
    type helm >/dev/null 2>&1 || { echo >&2 "I require helm but it is not installed.  Aborting."; exit 1; }
}

# echoc: Prints the user specified string to the screen using the specified colour.
#
# Parameters: ${1} - The string to print.
#             ${2} - The intensity of the colour.
#             ${3} - The colour to use for printing the string.
#
#             NOTE: The following color options are available:
#
#                   [0|1]30, [dark|light] black
#                   [0|1]31, [dark|light] red
#                   [0|1]32, [dark|light] green
#                   [0|1]33, [dark|light] yellow
#                   [0|1]34, [dark|light] blue
#                   [0|1]35, [dark|light] purple
#                   [0|1]36, [dark|light] cyan
#
echoc() {
    if [[ ${#} != 3 ]]; then
        echo "usage: ${FUNCNAME} <string> [light|dark] [black|red|green|yellow|blue|pruple|cyan]"
        exit 1
    fi

    local message=${1}

    case $2 in
        dark) intensity=0 ;;
        light) intensity=1 ;;
    esac

    if [[ -z $intensity ]]; then
        echo "${2} intensity not recognised"
        exit 1
    fi

    case $3 in 
        black) colour_code=${intensity}30 ;;
        red) colour_code=${intensity}31 ;;
        green) colour_code=${intensity}32 ;;
        yellow) colour_code=${intensity}33 ;;
        blue) colour_code=${intensity}34 ;;
        purple) colour_code=${intensity}35 ;;
        cyan) colour_code=${intensity}36 ;;
    esac
        
    if [[ -z $colour_code ]]; then
        echo "${1} colour not recognised"
        exit 1
    fi

    colour_code=${colour_code:1}

    # Print out the message
    echo "${message}" | awk '{print "\033['${intensity}';'${colour_code}'m" $0 "\033[1;0m"}'
}

#
# clean: Cleans the services, volumes, and pods from the Kubernetes cluster.
#
 clean() {
    HELM_RELEASES=$(helm list | tail -n +2 | awk '{ print $1 }')

    # Delete any existing releases
    if [[ ! -z ${HELM_RELEASES// /} ]]; then
        echo -n "Deleting the following helm releases: "
        echo ${HELM_RELEASES}...
        helm delete --purge ${HELM_RELEASES}
        sleep 2
    fi

    namespace=${1:-blockchain}
    # kubectl  --namespace $namespace delete pv,pvc,secret
    kubectl delete namespaces $namespace

    echo "Checking if all deployments are deleted"

    NUM_PENDING=$(kubectl get deployments | grep blockchain | wc -l | awk '{print $1}')
    while [ "${NUM_PENDING}" != "0" ]; do
        echo "Waiting for all blockchain deployments to be deleted. Remaining = ${NUM_PENDING}"
        NUM_PENDING=$(kubectl get deployments | grep blockchain | wc -l | awk '{print $1}')
        sleep 1;
    done

    NUM_PENDING=$(kubectl get svc | grep blockchain | wc -l | awk '{print $1}')
    while [ "${NUM_PENDING}" != "0" ]; do
        echo "Waiting for all blockchain services to be deleted. Remaining = ${NUM_PENDING}"
        NUM_PENDING=$(kubectl get svc | grep blockchain | wc -l | awk '{print $1}')
        sleep 1;
    done

    while [ "$(kubectl get pods | grep utils | wc -l | awk '{print $1}')" != "0" ]; do
        echo "Waiting for util pod to be deleted."
        sleep 1;
    done

    echo "All blockchain deployments & services have been removed"
}

#
# getPods: Updates the pod status variables.
#
 get_pod_status() {
    NAMESPACE=${1:-blockchain}
    PODS=$(kubectl get pods --namespace $NAMESPACE)
    PODS_RUNNING=$(echo "${PODS}" | grep Running | wc -l)
    PODS_COMPLETED=$(echo "${PODS}" | grep Completed | wc -l)
    PODS_ERROR=$(echo "${PODS}" | grep Error | wc -l)
}

#
# check_pod_status: Checks the status of all pods ensure the correct number are running,
#                 completed, and that none completed with errors.
#
# Parameters:     $1 - The expected number of pods in the 'Running' state.
#                 $2 - The expected number of pods in the 'Completed' state.
#
 check_pod_status() {
    # Ensure arguments were passed
    if [[ ${#} -ne 2 ]]; then
        echo "Usage: ${FUNCNAME} <num_running_pods> <num_completed_pods>"
        exit 1
    fi

    NUM_RUNNING=${1}
    NUM_COMPLETED=${2}

    # Get the status of the pods
    get_pod_status

    # Wait for the pods to initialize
    while [ "${PODS_RUNNING}" -ne ${NUM_RUNNING} ] || [ "${PODS_COMPLETED}" -ne ${NUM_COMPLETED} ]; do
        if [ "${PODS_ERROR}" -gt 0 ]; then
            echoc "$(basename $0): error: the following pods failed with errors:" light red
            echoc "$(echo "$PODS" | grep Error)" light red

            # Show the logs for failed pods
            for i in $(echo "$PODS" | grep Error | awk '{print $1}'); do
                # echoc "kubectl describe pod ${i}" light green
                # kubectl describe pod "${i}"

                if [[ ${i} =~ .*channel-create.* ]]; then
                    echoc "kubectl logs ${i} createchanneltx" light green
                    kubectl logs "${i}" "createchanneltx"

                    echoc "kubectl logs ${i} createchannel" light green
                    kubectl logs "${i}" "createchannel"
                else
                    echoc "kubectl logs ${i}" light green
                    kubectl logs "${i}"
                fi
            done

            exit -1
        fi

        echoc "Waiting for the pods to initialize..." light blue
        sleep 2

        get_pod_status
    done

    echoc "Pods initialized successfully!\n" light blue
}

#
# lint_chart: Lints the helm chart in the current working directory.
#
lint_chart() {
    LINT_OUTPUT=$(helm lint .)

    if [[ ${?} -ne 0 ]]; then
        echoc "\n$(basename $0): error: '$(basename $(pwd))' linting failed with errors:" light red
        echoc "${LINT_OUTPUT}" light red
        exit -1
    fi
}

simple_setup() {
    local base_path="${PWD}/blockchain"
    local chaincode_path="../../${base_path}/chaincode"
    local chaincode_name="mychaincode"
    local channel_name="mychannel"

    clean

    RELEASE_NAME="fabric"
    TOTAL_RUNNING=7
    TOTAL_COMPLETED=2

    # Move into the directory
    pushd blockchain >/dev/null 2>&1

    namespace=${1:-blockchain}

    # Install the chart
    lint_chart
    echoc "helm install --namespace $namespace --name ${RELEASE_NAME} ." light green
    helm install --namespace $namespace --name ${RELEASE_NAME} .

    # Copy config
    UTILSSTATUS=$(kubectl get pods --namespace $namespace | grep utils | awk '{print $3}')
    while [ "${UTILSSTATUS}" != "Running" ]; do
        echo "Waiting for utils pod to start. Status = ${UTILSSTATUS}"
        sleep 5
        if [ "${UTILSSTATUS}" == "Error" ]; then
            echo "There is an error in utils pod. Please run 'kubectl logs utils' or 'kubectl describe pod utils'."
            exit 1
        fi
        UTILSSTATUS=$(kubectl get pods --namespace $namespace | grep utils | awk '{print $3}')
    done

    sleep 2

    echoc "Copying configuration data to shared volume" light cyan
    test -d "./config" && echo Exists || echo Does not exist
    kubectl --namespace $namespace cp ./config utils:/shared/config

    check_pod_status ${TOTAL_RUNNING} ${TOTAL_COMPLETED}

    peer1org1_pod=$(kubectl get pods --namespace $namespace -l "app=blockchain,release=${RELEASE_NAME},name=blockchain-org1peer1" -o jsonpath="{.items[0].metadata.name}")
    peer1org2_pod=$(kubectl get pods --namespace $namespace -l "app=blockchain,release=${RELEASE_NAME},name=blockchain-org2peer1" -o jsonpath="{.items[0].metadata.name}")
   
    echoc "Creating and fetching channel" light blue
    kubectl exec --namespace $namespace $peer1org1_pod -- peer channel create -o blockchain-orderer:31010 -c mychannel -f /shared/mychannel.tx
    kubectl exec --namespace $namespace $peer1org1_pod -- peer channel fetch config /shared/mychannel.block -c mychannel -o blockchain-orderer:31010

    echoc "$peer1org1_pod joining channel" light blue
    kubectl exec --namespace $namespace $peer1org1_pod -- peer channel join -b /shared/mychannel.block

    echoc "$peer1org2_pod joining channel" light blue
    kubectl exec --namespace $namespace $peer1org2_pod -- peer channel join -b /shared/mychannel.block

    cli_pod=$(kubectl get pods --namespace $namespace -l "app=blockchain,release=${RELEASE_NAME},name=blockchain-cli" -o jsonpath="{.items[0].metadata.name}")

    echoc "Copying chaincode codebase into peer container" light blue
    kubectl exec --namespace $namespace $cli_pod -- bash -c "mkdir -p /opt/gopath/src"
    kubectl cp --namespace $namespace $chaincode_path ${cli_pod}:/opt/gopath/src/chaincode
    
    echoc "Installing chaincode" light blue
    kubectl exec --namespace $namespace $cli_pod -- bash -c "peer chaincode install -n $chaincode_name -v 1.0 -p chaincode/${chaincode_name}"
    
    echoc "Instantiating chaincode" light blue
    kubectl exec --namespace $namespace $cli_pod -- bash -c "peer chaincode instantiate -n $chaincode_name -v 1.0 -C $channel_name -o blockchain-orderer:31010 -l golang -c '{\"Args\":[]}' -P \"OR('Org1MSP.member', 'Org2MSP.member')\" "
    
    wait 10
    
    echoc "Test invoke" light blue
    kubectl exec --namespace $namespace $cli_pod -- bash -c "peer chaincode invoke -o blockchain-orderer:31010 -C $channel_name -n $chaincode_name -c '{\"Args\":[\"put\",\"a\",\"10\"]}'"
    
    popd >/dev/null 2>&1
}

interactive_setup() {
    export base_path="${PWD}/hlf"
    export cryptos_path="${base_path}/cryptos"
    export chaincode_path="${base_path}/../../chaincode"
    export chaincode_name="mychaincode"

    echoc "=======================================================" light cyan
    echoc "===== Fabric on Kubernetes - Official Helm Charts =====" light cyan
    echoc "=======================================================" light cyan

    echo
    echoc "Setting up the network" light blue
    echo

    if [ -d "$cryptos_path" ]; then
        echoc "crypto-config already exists" light yellow
		read -p "Do you wish to remove crypto-config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) rm -rf $cryptos_path ;;
			* ) ;;
    	esac
    fi

    read -p "Organisations [1]: " orgs
    orgs=${orgs:-1}
    echoc $orgs light green

    read -p "Peers per org [1]: " peers
    peers=${peers:-1}
    echoc $peers light green

    read -p "CAs per org [1]: " cas
    cas=${cas:-1}
    echoc $cas light green

    read -p "Orderers per org [1]: " orderers
    orderers=${orderers:-1}
    echoc $orderers light green

    echoc "================================" light cyan
    echoc "==== Configuring Kubernetes ====" light cyan
    echoc "================================" light cyan
    
    read -p "Namespace [blockchain]: " namespace
    export namespace=${namespace:-blockchain}
    echoc $namespace light green

    # It is not always working. It depends on the permissions assigned to the user. Leave it manual for now.
    # kubectl create namespace $namespace >/dev/null 2>&1 || { echo >&2 "Not enough permissions to create a namespace."; exit 1; }

    # Repository that works also in country with restricted connectivity (such as China)
    # helm init --service-account tiller --tiller-namespace $namespace --tiller-image registry.cn-hangzhou.aliyuncs.com/google_containers/tiller:v2.14.2 --upgrade

    # echoc "Waiting for tiller container to be up and running..." light blue
    # sleep 10

    create_ca

    org_msp="Org1MSP"

    create_admin $org_msp

    create_orderer

    create_peer

    create_couchdb
    
    read -p "Channel [mychannel]: " channel_name
    channel_name=${channel_name:-mychannel}
    echoc $channel_name light green

    generate_genesis $base_path ${base_path}/config $cryptos_path OneOrgOrdererGenesis
    generate_channeltx $channel_name $base_path ${base_path}/config $cryptos_path OneOrgOrdererGenesis OneOrgChannel Org1MSP

    kubectl create secret generic --namespace $namespace hlf--${channel_name}-genesis --from-file=genesis.block=${base_path}/channels/orderer-system-channel/genesis_block.pb
    kubectl create secret generic --namespace $namespace hlf--${channel_name}-channel --from-file=${base_path}/channels/$channel_name/${channel_name}_tx.pb --from-file=${base_path}/channels/$channel_name/${org_msp}_anchors_tx.pb

    echoc "Checking if Orderer already exists" light yellow
    orderer_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-ord,release=${orderer_name}" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ -z $orderer_pod ]; then
        echoc "Create and set up Orderer" light blue
        helm install ./hlf/charts/hlf-ord --namespace $namespace --tiller-namespace $namespace --name $orderer_name --set image.tag=${FABRIC_VERSION},service.port=${orderer_port},ord.mspID=${orderer_msp},ord.type=${orderer_type},secrets.ord.cert=hlf--${orderer_name}-idcert,secrets.ord.key=hlf--${orderer_name}-idkey,secrets.ord.caCert=hlf--ca-cert,secrets.genesis=hlf--${channel_name}-genesis,secrets.adminCert=hlf--${orderer_name}-admincert
    else
        echoc "Orderer exists. Continuing.." light green
    fi

    echoc "Checking if Peer already exists" light yellow
    peer_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-peer,release=${peer_name}" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ -z $peer_pod ]; then
        echoc "Create and set up Peer" light blue
        helm install ./hlf/charts/hlf-peer --namespace $namespace --tiller-namespace $namespace --name $peer_name --set image.tag=${FABRIC_VERSION},peer.couchdbInstance=cdb-${peer_name},peer.mspID=${peer_msp},service.portRequest=${peer_port},secrets.peer.cert=hlf--${peer_name}-idcert,secrets.peer.key=hlf--${peer_name}-idkey,secrets.peer.caCert=hlf--ca-cert,secrets.channel=hlf--${channel_name}-channel,secrets.adminCert=hlf--${org}-admincert,secrets.adminKey=hlf--${org}-adminkey,peer.gossip.bootstrap=${peer_name}-hlf-peer:${peer_port},peer.gossip.externalEndpoint=${peer_name}-hlf-peer:${peer_port}
    else
        echoc "Peer exists. Continuing.." light green
    fi

    orderer_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-ord,release=${orderer_name}" -o jsonpath="{.items[0].metadata.name}")
    status=$(kubectl describe pod --namespace $namespace -l "app=hlf-ord,release=${orderer_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    while [ "${status}" != "True" ]; do
        echoc "Waiting for ${orderer_name} to start. Status = ${status}" light purple
        sleep 5
        if [ "${status}" == "Error" ]; then
            echoc "There is an error in ${orderer_name}. Please run 'kubectl logs ${orderer_name}' or 'kubectl describe pod ${orderer_name}'." light red
            exit 1
        fi
        status=$(kubectl describe pod --namespace $namespace -l "app=hlf-ord,release=${orderer_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    done

    peer_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-peer,release=${peer_name}" -o jsonpath="{.items[0].metadata.name}")
    status=$(kubectl describe pod --namespace $namespace -l "app=hlf-peer,release=${peer_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    while [ "${status}" != "True" ]; do
        echoc "Waiting for ${peer_name} to start. Status = ${status}" light purple
        sleep 5
        if [ "${status}" == "Error" ]; then
            echoc "There is an error in ${peer_name}. Please run 'kubectl logs ${peer_name}' or 'kubectl describe pod ${peer_name}'." light red
            exit 1
        fi
        status=$(kubectl describe pod --namespace $namespace -l "app=hlf-peer,release=${peer_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    done

    echoc "Create channel" light blue
    kubectl exec --namespace $namespace $peer_pod -- bash -c "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp peer channel create -o ${orderer_name}-hlf-ord:${orderer_port} -c $channel_name -f /hl_config/channel/${channel_name}_tx.pb"

    echoc "Fetch channel" light blue
    kubectl exec --namespace $namespace $peer_pod -- bash -c "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp peer channel fetch config /${channel_name}.block -c $channel_name -o ${orderer_name}-hlf-ord:${orderer_port}"

    echoc "Join channel" light blue
    kubectl exec --namespace $namespace $peer_pod -- bash -c "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp peer channel join -b /${channel_name}.block"

    echoc "Update channel with anchor peers" light blue
    kubectl exec --namespace $namespace $peer_pod -- bash -c "CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp peer channel update -o ${orderer_name}-hlf-ord:${orderer_port} -c $channel_name -f /hl_config/channel/${org_msp}_anchors_tx.pb"

    cli_name=cli
    
    echoc "Checking if CLI already exists" light yellow
    cli_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-tools,release=${cli_name}" -o jsonpath="{.items[0].metadata.name}")

    if [ -z $cli_pod ]; then
        echoc "Create and set up CLI" light blue
        helm install ./hlf/charts/hlf-tools --namespace $namespace --tiller-namespace $namespace --name $cli_name --set image.tag=${FABRIC_VERSION},peer.host=${peer_name}-hlf-peer,peer.port=${peer_port},peer.mspID=${org_msp},secrets.peer.cert=hlf--${peer_name}-idcert,secrets.peer.key=hlf--${peer_name}-idkey,secrets.peer.caCert=hlf--ca-cert,secrets.channel=hlf--${channel_name}-channel,secrets.adminCert=hlf--${org}-admincert,secrets.adminKey=hlf--${org}-adminkey
    else
        echoc "CLI exists. Continuing.." light green
    fi

    cli_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-tools,release=${cli_name}" -o jsonpath="{.items[0].metadata.name}")
    status=$(kubectl describe pod --namespace $namespace -l "app=hlf-tools,release=${cli_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    while [ "${status}" != "True" ]; do
        echoc "Waiting for ${cli_name} to start. Status = ${status}" light purple
        sleep 5
        if [ "${status}" == "Error" ]; then
            echoc "There is an error in ${cli_name}. Please run 'kubectl logs ${cli_name}' or 'kubectl describe pod ${cli_name}'." light red
            exit 1
        fi
        status=$(kubectl describe pod --namespace $namespace -l "app=hlf-tools,release=${cli_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    done

    echo "Copying chaincode codebase into peer container"
    kubectl exec --namespace $namespace $cli_pod -- bash -c "mkdir -p /opt/gopath/src"
    kubectl cp --namespace $namespace $chaincode_path ${cli_pod}:/opt/gopath/src/chaincode

    echoc "Install default chaincode" light blue
    kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_name}-hlf-peer:${peer_port} peer chaincode install -n $chaincode_name -v 1.0 -p chaincode/${chaincode_name}"
    
    echoc "Instantiate default chaincode" light blue
    kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_name}-hlf-peer:${peer_port} peer chaincode instantiate -o ${orderer_name}-hlf-ord:${orderer_port} -n $chaincode_name -v 1.0 -C ${channel_name} -l golang -c '{\"Args\":[]}' -P \"OR('Org1MSP.member')\""
    
    sleep 5
    
    echoc "Test invoke" light blue
    kubectl exec --namespace $namespace $cli_pod -- bash -c "CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_MSPCONFIGPATH=/var/hyperledger/admin_msp CORE_PEER_ADDRESS=${peer_name}-hlf-peer:${peer_port} peer chaincode invoke -o ${orderer_name}-hlf-ord:${orderer_port} -C $channel_name -n $chaincode_name -c '{\"Args\":[\"put\",\"a\",\"10\"]}'"
}

create_ca() {
    echoc "===============================" light blue
    echoc "==== Certificate Authority ====" light blue
    echoc "===============================" light blue

    ca_port="30054"

    read -p "CA name [ca]: " ca_name
    export ca_name=${ca_name:-ca}
    echoc $ca_name light green

    echoc "Checking if CA already exists" light yellow
    ca_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-ca,release=${ca_name}" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ ! -z $ca_pod ]; then
        echoc "CA exists. Continuing.." light green
        return
    fi

    echoc "Create and set up CA" light blue
    helm install ./hlf/charts/hlf-ca --namespace $namespace --tiller-namespace $namespace --name $ca_name --set image.tag=${FABRIC_VERSION},config.hlfToolsVersion=${FABRIC_VERSION},service.port=${ca_port},caName=${ca_name},postgresql.enabled=true

    ca_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-ca,release=${ca_name}" -o jsonpath="{.items[0].metadata.name}")
    status=$(kubectl describe pod --namespace $namespace -l "app=hlf-ca,release=${ca_name}" | grep -m2 "Ready" | tail -n1 |  awk '{print $2}')
    while [ "${status}" != "True" ]; do
        echoc "Waiting for $ca_pod to start. Status = ${status}" light purple
        sleep 5
        if [ "${status}" == "Error" ]; then
            echoc "There is an error in $ca_pod. Please run 'kubectl logs $ca_pod' or 'kubectl describe pod $ca_pod'." light red
            exit 1
        fi
        status=$(kubectl describe pod --namespace $namespace -l "app=hlf-ca,release=${ca_name}" | grep -m2 "Ready" | tail -n1 |  awk '{print $2}')
    done

    kubectl exec --namespace $namespace $ca_pod -- bash -c 'fabric-ca-client enroll -d -u http://$CA_ADMIN:$CA_PASSWORD@$SERVICE_DNS:7054'
}

create_admin() {
    if [ -z "$1" ]; then
		echoc "MSP missing" light red
		exit 1
	fi

    local org_msp="$1"
    export org=`echo "$org_msp" | awk '{print tolower($0)}'`

    echoc "Checking if Admin has been already registered" light yellow
    cert=$(kubectl get secrets --namespace $namespace | grep "hlf--${org}-admincert")
    key=$(kubectl get secrets --namespace $namespace | grep "hlf--${org}-adminkey")
    
    if [ ! -z "$cert" ] && [ ! -z "$key" ]; then
        echoc "Admin already registered. Continuing.." light green
        return
    fi

    echoc "Register organisation admin" light blue
    read -p "Admin name [org1-admin]: " admin_name
    admin_name=${admin_name:-org1-admin}
    echoc $admin_name light green

    read -p "Admin secret [OrgAdm1nPW]: " admin_secret
    admin_secret=${admin_secret:-OrgAdm1nPW}
    echoc $admin_secret light green

    echoc "Register the Organisation Admin identity" light blue
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client register --id.name $admin_name --id.secret $admin_secret --id.attrs '"hf.Registrar.Roles=peer,user,client",hf.Registrar.Attributes=*,hf.Revoker=true,hf.GenCRL=true,admin=true:ecert,abac.init=true:ecert' -u http://$SERVICE_DNS:7054

    echoc "Enroll the Organisation Admin identity in $org_msp" light blue
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client enroll -u http://${admin_name}:${admin_secret}@$SERVICE_DNS:7054 -M $org_msp

    echoc "Copying credentials to local" light blue
    kubectl cp --namespace $namespace $ca_pod:/var/hyperledger/fabric-ca/$org_msp ${cryptos_path}/${org_msp}

    mkdir -p ${cryptos_path}/${org_msp}/admincerts
    cp ${cryptos_path}/${org_msp}/signcerts/* ${cryptos_path}/${org_msp}/admincerts

    echoc "Add org-admincert secret" light blue
    org_cert=$(ls ${cryptos_path}/${org_msp}/admincerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--${org}-admincert --from-file=cert.pem=$org_cert

    echoc "Add org-adminkey secret" light blue
    org_key=$(ls ${cryptos_path}/${org_msp}/keystore/*_sk)
    kubectl create secret generic --namespace $namespace hlf--${org}-adminkey --from-file=key.pem=$org_key
}

create_orderer() {
    echoc "=================" light blue
    echoc "==== Orderer ====" light blue
    echoc "=================" light blue

    echoc "Register Orderer to CA" light blue

    read -p "Orderer name [orderer]: " orderer_name
    export orderer_name=${orderer_name:-orderer}
    echoc $orderer_name light green

    read -p "Orderer secret [orderer_pw]: " orderer_secret
    orderer_secret=${orderer_secret:-orderer_pw}
    echoc $orderer_secret light green

    export orderer_msp="OrdererMSP"
    export orderer_port="31010"
    export orderer_type="solo"

    echoc "Checking if Orderer has been already registered" light yellow
    cert=$(kubectl get secrets --namespace $namespace | grep "hlf--${orderer_name}-idcert")
    key=$(kubectl get secrets --namespace $namespace | grep "hlf--${orderer_name}-idkey")
    
    if [ ! -z "$cert" ] && [ ! -z "$key" ]; then
        echoc "Orderer already registered. Continuing.." light green
        return
    fi

    echoc "Register $orderer_name" light blue
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client register --id.name $orderer_name --id.secret $orderer_secret --id.type orderer

    echoc "Enroll $orderer_name" light blue
    kubectl exec --namespace $namespace $ca_pod -- fabric-ca-client enroll -d -u http://${orderer_name}:${orderer_secret}@$SERVICE_DNS:7054 -M $orderer_msp

    echoc "Copying credentials to local" light blue
    kubectl cp --namespace $namespace $ca_pod:/var/hyperledger/fabric-ca/${orderer_msp} ${cryptos_path}/${orderer_msp}

    mkdir -p ${cryptos_path}/${orderer_msp}/admincerts
    cp ${cryptos_path}/${orderer_msp}/signcerts/* ${cryptos_path}/${orderer_msp}/admincerts

    echoc "Add orderer public certificate" light blue
    orderer_cert=$(ls ${cryptos_path}/${orderer_msp}/admincerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--${orderer_name}-idcert --from-file=cert.pem=${orderer_cert}
    kubectl create secret generic --namespace $namespace hlf--${orderer_name}-admincert --from-file=cert.pem=${orderer_cert}

    echoc "Add orderer signining private key" light blue
    orderer_key=$(ls ${cryptos_path}/${orderer_msp}/keystore/*_sk)
    kubectl create secret generic --namespace $namespace hlf--${orderer_name}-idkey --from-file=key.pem=${orderer_key}

    echoc "Add cacert secret" light blue
    ca_cert=$(ls ${cryptos_path}/${orderer_msp}/cacerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--ca-cert --from-file=cacert.pem=$ca_cert
}

create_peer() {
    echoc "==============" light blue
    echoc "==== Peer ====" light blue
    echoc "==============" light blue

    echoc "Register Peer to CA" light blue
    read -p "Peer name [org1peer1]: " peer_name
    export peer_name=${peer_name:-org1peer1}
    echoc $peer_name light green

    read -p "Peer secret [org1peer1_pw]: " peer_secret
    peer_secret=${peer_secret:-org1peer1_pw}
    echoc $peer_secret light green

    export peer_msp="Org1MSP"
    export peer_port="30110"

    echoc "Checking if Peer has been already registered" light yellow
    cert=$(kubectl get secrets --namespace $namespace | grep "hlf--${peer_name}-idcert")
    key=$(kubectl get secrets --namespace $namespace | grep "hlf--${peer_name}-idkey")
    
    if [ ! -z "$cert" ] && [ ! -z "$key" ]; then
        echoc "Peer already registered. Continuing.." light green
        return
    fi

    echoc "Add peer public certificate" light blue
    peer_cert=$(ls ${cryptos_path}/${peer_msp}/signcerts/*.pem)
    kubectl create secret generic --namespace $namespace hlf--${peer_name}-idcert --from-file=cert.pem=${peer_cert}

    echoc "Add peer signining private key" light blue
    peer_key=$(ls ${cryptos_path}/${peer_msp}/keystore/*_sk)
    kubectl create secret generic --namespace $namespace hlf--${peer_name}-idkey --from-file=key.pem=${peer_key}
}

create_couchdb() {
    echoc "=================" light blue
    echoc "==== CouchDB ====" light blue
    echoc "=================" light blue

    echoc "Checking if CouchDB already exists" light yellow
    cdb_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-couchdb,release=cdb-${peer_name}" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ ! -z $cdb_pod ]; then
        echoc "CouchDB exists. Continuing.." light green
        return
    fi

    echoc "Create and set up CouchDB state to attach to ${peer_name}" light blue
    helm install stable/hlf-couchdb --namespace $namespace --tiller-namespace $namespace --name cdb-${peer_name} --set image.tag=${THIRDPARTY_VERSION}
    
    cdb_pod=$(kubectl get pods --namespace $namespace -l "app=hlf-couchdb,release=cdb-${peer_name}" -o jsonpath="{.items[0].metadata.name}")
    status=$(kubectl describe pod --namespace $namespace -l "app=hlf-couchdb,release=cdb-${peer_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    while [ "${status}" != "True" ]; do
        echoc "Waiting for cdb-${peer_name} to start. Status = ${status}" light purple
        sleep 5
        if [ "${status}" == "Error" ]; then
            echoc "There is an error in cdb-${peer_name}. Please run 'kubectl logs cdb-${peer_name}' or 'kubectl describe pod cdb-${peer_name}'." light red
            exit 1
        fi
        status=$(kubectl describe pod --namespace $namespace -l "app=hlf-couchdb,release=cdb-${peer_name}" | grep -m2 "Ready" | head -n1 |  awk '{print $2}')
    done
}

# generate genesis block
# $1: base path
# $2: config path
# $3: cryptos directory
# $4: network profile name
generate_genesis() {
    if [ -z "$1" ]; then
		echoc "Base path missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$3" ]; then
		echoc "Crypto material path missing" dark red
		exit 1
	fi
    if [ -z "$4" ]; then
		echoc "Network profile name" dark red
		exit 1
	fi

    local base_path="$1"
    local config_path="$2"
    local channel_dir="${base_path}/channels/orderer-system-channel"
    local cryptos_path="$3"
    local network_profile="$4"

    if [ -d "$channel_dir" ]; then
        echoc "Channel directory ${channel_dir} already exists" light yellow
		read -p "Do you wish to re-generate channel config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) ;;
			* ) return 0
    	esac
        rm -rf $channel_dir
        mkdir -p $channel_dir
    fi

    echoc "========================" dark cyan
    echoc "Generating genesis block" dark cyan
    echoc "========================" dark cyan
    echo
	echoc "Base path: $base_path" light cyan
	echoc "Config path: $config_path" light cyan
	echoc "Cryptos path: $cryptos_path" light cyan
	echoc "Network profile: $network_profile" light cyan

    # generate genesis block for orderer
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/orderer-system-channel \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    bash -c " \
                        configtxgen -profile $network_profile -channelID orderer-system-channel -outputBlock /channels/orderer-system-channel/genesis_block.pb /configtx.yaml;
                        configtxgen -inspectBlock /channels/orderer-system-channel/genesis_block.pb
                    "
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate orderer genesis block..." dark red
		exit 1
	fi
}

# generate channel config
# $1: channel_name
# $2: base path
# $3: configtx.yml file path
# $4: cryptos directory
# $5: network profile name
# $6: channel profile name
# $7: org msp
generate_channeltx() {
    if [ -z "$1" ]; then
		echoc "Channel name missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Base path missing" dark red
		exit 1
	fi
    if [ -z "$3" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$4" ]; then
		echoc "Crypto material path missing" dark red
		exit 1
	fi
    if [ -z "$5" ]; then
		echoc "Network profile missing" dark red
		exit 1
	fi
    if [ -z "$6" ]; then
		echoc "Channel profile missing" dark red
		exit 1
	fi
    if [ -z "$7" ]; then
		echoc "MSP missing" dark red
		exit 1
	fi

	local channel_name="$1"
    local base_path="$2"
    local config_path="$3"
    local cryptos_path="$4"
    local channel_dir="${base_path}/channels/${channel_name}"
    local network_profile="$5"
    local channel_profile="$6"
    local org_msp="$7"

    if [ -d "$channel_dir" ]; then
        echoc "Channel directory ${channel_dir} already exists" light yellow
		read -p "Do you wish to re-generate channel config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) ;;
			* ) return 0
    	esac
        rm -rf $channel_dir
        mkdir -p $channel_dir
    fi 

    echoc "=========================" dark cyan
    echoc "Generating channel config" dark cyan
    echoc "=========================" dark cyan
    echo
	echoc "Channel: $channel_name" light cyan
	echoc "Base path: $base_path" light cyan
	echoc "Config path: $config_path" light cyan
	echoc "Cryptos path: $cryptos_path" light cyan
	echoc "Channel dir: $channel_dir" light cyan
	echoc "Network profile: $network_profile" light cyan
	echoc "Channel profile: $channel_profile" light cyan
	echoc "Org MSP: $org_msp" light cyan

	# generate channel configuration transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    bash -c " \
                        configtxgen -profile $channel_profile -outputCreateChannelTx /channels/${channel_name}/${channel_name}_tx.pb -channelID $channel_name /configtx.yaml;
                        configtxgen -inspectChannelCreateTx /channels/${channel_name}/${channel_name}_tx.pb
                    "
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate channel configuration transaction..." dark red
		exit 1
	fi

	# generate anchor peer transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    configtxgen -profile $channel_profile -outputAnchorPeersUpdate /channels/${channel_name}/${org_msp}_anchors_tx.pb -channelID $channel_name -asOrg $org_msp /configtx.yaml
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate anchor peer update for $org_msp..." dark red
		exit 1
	fi
}

# generate crypto config
# $1: crypto-config.yml file path
# $2: certificates output directory
generate_cryptos() {
    if [ -z "$1" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Cryptos path missing" dark red
		exit 1
	fi

    local config_path="$1"
    local cryptos_path="$2"

    echoc "==================" dark cyan
    echoc "Generating cryptos" dark cyan
    echoc "==================" dark cyan
    echo
    echoc "Config path: $config_path" light cyan
    echoc "Cryptos path: $cryptos_path" light cyan

    if [ -d "$cryptos_path" ]; then
        echoc "crypto-config already exists" light yellow
		read -p "Do you wish to remove crypto-config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) rm -rf $cryptos_path ;;
			* ) ;;
    	esac
    fi

    if [ ! -d "$cryptos_path" ]; then
        mkdir -p $cryptos_path

        # generate crypto material
        docker run --rm -v ${config_path}/crypto-config.yaml:/crypto-config.yaml \
                        -v ${cryptos_path}:/crypto-config \
                        hyperledger/fabric-tools:${FABRIC_VERSION} \
                        cryptogen generate --config=/crypto-config.yaml --output=/crypto-config
        if [ "$?" -ne 0 ]; then
            echoc "Failed to generate crypto material..." dark red
            exit 1
        fi
    fi
    
    # copy cryptos into a shared folder available for client applications (sdk)
    if [ -d "${CRYPTOS_SHARED_PATH}" ]; then
        echoc "Shared crypto-config directory ${CRYPTOS_SHARED_PATH} already exists" light yellow
		read -p "Do you wish to copy the new crypto-config here? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) 
                rm -rf ${CRYPTOS_SHARED_PATH}
            ;;
			* ) return 0
    	esac
    fi
    mkdir -p ${CRYPTOS_SHARED_PATH}
    cp -r ${cryptos_path}/** ${CRYPTOS_SHARED_PATH}
}

help () {
    help="
==============================
==== Fabric on Kubernetes ====
==============================
help                                    : this help
start                                   : run a simple 2-orgs setup; no secrets; no data persistency; shared volumes
start [-i|prod]                         : run an interactive setup using secrets and separated volumes with data persistency
clean [namespace]                       : wipe the environment out by namespace (default: blockchain)
generate [cryptos|genesis|channeltx]    : generate any of the configuration file
"
    echoc "$help" light cyan
}

readonly func="$1"
shift

check_dependecies

if [ "$func" == "start" ]; then
    if [ "$1" = "-i" ] || [ "$1" = "prod" ]; then
        interactive_setup
    else
        simple_setup
    fi
elif [ "$func" == "generate" ]; then
    readonly param="$1"
    shift
    if [ "$param" == "cryptos" ]; then
        generate_cryptos $@
    elif [ "$param" == "genesis" ]; then
        generate_genesis $@
    elif [ "$param" == "channeltx" ]; then
        generate_channeltx $@
    fi
elif [ "$func" == "clean" ]; then
    clean $@
else
    help
    exit 1
fi