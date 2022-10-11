#!/bin/bash

if [[ "$1" == "" ]]; then
    theNetwork=docker_network
else
    theNetwork=$1
fi


if [[ "`command -v docker`" == "" ]]; then
    echo "Docker not installed on this machine"
    exit 1
elif [[ "`command -v jq`" == "" ]]; then
    echo "jq must be installed, exiting"
    exit 1
fi

printf "#\n# Network : ${theNetwork}\n#\n" 

FILE=`realpath ./${theNetwork}.env`
if [ ! -f $FILE ]; then
    echo "Definition file '${FILE}' does not exist, cannot proceed"
    exit 1
fi

. $FILE

if [[ -z ${nwSubnet+x} ||  -z ${nwGateway+x} || -z ${nwDHCPrange+x} ]]; then
    echo "Required variables not all specified, cannot proceed"
    exit 1
fi

nwID_old=`docker network ls -f "name=^$theNetwork$" -q --no-trunc`


if [[ ! "${nwID_old}" == "" ]]; then

    configOld=`docker network inspect ${nwID_old} | jq '.[].IPAM.Config[0]'`

    oldSubnet=$(jq -r '.Subnet' <<< $configOld)
    oldGateway=$(jq -r '.Gateway' <<< $configOld)
    oldDHCPrange=$(jq -r '.IPRange' <<< $configOld)

    # if [[ "${nwSubnet}" == "${oldSubnet}" &&  "${nwGateway}" == "${oldGateway}" &&  "${nwDHCPrange}" == "${oldDHCPrange}" ]]; then
    #     echo "Network definition unchanged. Leaving"
    #     exit 0
    # fi

    docker network inspect ${nwID_old} | jq
    docker network inspect ${nwID_old} | jq > ./${theNetwork}.txt

    disconnectCount=0
    my_array=( `docker network inspect -f '{{range .Containers}}{{.Name}}{{printf ";"}}{{.IPv4Address}}{{printf ";"}}{{.IPv6Address}}{{printf "\n"}}{{end}}' ${nwID_old}` )

    for thisContainer in "${my_array[@]}"; do
        if ! [ "$thisContainer" == "" ]; then
            if [[ $disconnectCount -eq 0 ]]; then
                printf "#\n# Disconnecting containers\n#\n"
            fi
            ((disconnectCount=disconnectCount+1))
            # echo $thisContainer
            IFS=';' read -ra arrIN <<< "$thisContainer"
            theCommand="docker network disconnect ${theNetwork} ${arrIN[0]}"
            echo $theCommand
            $theCommand
        fi
    done
    theCommand="docker network rm ${theNetwork}"
    printf "#\n# Drop network\n#\n"
    echo $theCommand
    $theCommand > /dev/null
fi


function addIfThere () {
    theVal=$2
    theTag=$1
    subTag=$3
    if [[ ! "$theVal" == "" ]]; then
        theLine="${theTag} "
        if [[ ! "$subTag" == "" ]]; then
            theLine+="${subTag}="
        fi
        theLine+="${theVal}"
        echo " $theLine"
    fi
}
function addIfOne () {
    theVal=$2
    theTag=$1
    if [[ $theVal -eq 1 ]]; then
        echo " ${theTag}"
    fi
}
theCommand="docker network create"
theCommand+=$(addIfThere "--driver" "$driver")
theCommand+=$(addIfThere "--subnet" "$nwSubnet")
theCommand+=$(addIfThere "--gateway" "$nwGateway")
theCommand+=$(addIfThere "--ip-range" "$nwDHCPrange")
theCommand+=$(addIfThere "-o" "${parent}" "parent")

theCommand+=" $theNetwork"
# nwID_new=`docker network create -d bridge --subnet $nwSubnet --gateway $nwGateway --ip-range $nwDHCPrange "$theNetwork"`

printf "#\n# Create network\n#\n"
echo $theCommand
nwID_new=`$theCommand`

if [[ ! "$nwID_old" == "" && $disconnectCount -gt 0 ]]; then
    printf "#\n# Reconnecting containers\n#\n"
    if [[ "${nwSubnet}" == "${oldSubnet}" ]]; then
        restoreOldIP=1
    else
        restoreOldIP=0
    fi
    for thisContainer in "${my_array[@]}"; do
        if ! [ "$thisContainer" == "" ]; then
            # echo $thisContainer
            IFS=';' read -ra arrIN <<< "$thisContainer"
            thisName=${arrIN[0]}
            thisIPV4=${arrIN[1]}
            thisIPV6=${arrIN[2]}
            theCommand="docker network connect "
            if [[ $restoreOldIP -eq 1 ]]; then
                function thisOne () {
                    thisIP=$1
                    if [[ ! "${thisIP}" == "" ]]; then
                        thisIP=( ${thisIP//\// } )
                        echo "--ip${2} ${thisIP} "
                    fi
                }
                theCommand+=`thisOne "${thisIPV4}"`
                theCommand+=`thisOne "${thisIPV6}" 6`
            fi
            theCommand+="${theNetwork} ${thisName}"
            echo $theCommand
            $theCommand > /dev/null
        fi
    done
fi

docker network inspect ${nwID_new} | jq 
docker network inspect ${nwID_new} | jq >> ./${theNetwork}.txt
