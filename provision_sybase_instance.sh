#!/bin/bash
#
# provision_sybase.sh
# Created: Javier Barthe - 12/2021
#
#   No utiliza ningun parametro, todo es tomado desde CFG File
#   Ejemplo de Ejecución: ./provision_sybase.sh
# Changelog:
#
# Date       Author              Description
# ---------- ------------------- ----------------------------------------------------
#  12/2021    Javier Barthe       Primera versión con CFG File. Sin parametros.
#====================================================================================

################################
# CARGA VARIABLES DE CFG       #
################################
while read line
do
  var=$(echo $line | awk -F= '{print $1}')
  value=$(echo $line | awk -F= '{print $2}')
  export "$var"="$value"
done < <(cat ./sybase.cfg |grep -v "#")
################################
# CONFIGURA CURL Y URL A HTTPS #
################################
case $HTTPS in
  "TRUE")
   CURL="curl -k"
   DELPHIX_ENGINE="https://${DELPHIX_IP}/resources/json/delphix"
    ;;
  "FALSE")
   CURL="curl"
   DELPHIX_ENGINE="http://${DELPHIX_IP}/resources/json/delphix"
    ;;
esac
################################
# TOMO EL PROXIMO NUMERO DE INSTANCIA                    #
################################
PREV_NUMBER=$INSTANCE_NUMBER
cp $RESOURCE_FILE ${RESOURCE_FILE}.bak
sed -i "s/NN/0${INSTANCE_NUMBER}/" ${RESOURCE_FILE}.bak
sed -i "s/DBN/DB${INSTANCE_NUMBER}/" ${RESOURCE_FILE}.bak
((INSTANCE_NUMBER++))
sed -i "s/INSTANCE_NUMBER=${PREV_NUMBER}/INSTANCE_NUMBER=${INSTANCE_NUMBER}/g" $CFG_FILE_LOCATION
################################
# FUNCIONES                    #
################################
buildSybase()
{
  . ${SYBASE_BIN}/SYBASE.sh
 echo "Iniciando Instancia Sybase.....espere.."
 srvbuildres -s $SYBASE -I ${SYBASE}/interfaces -r $RESOURCE_FILE.bak > $RESOURCE_FILE.$$.log
 #cat $RESOURCE_FILE.$$.log 
  # configure devices
  isql -Usa -Ppassw0rd -SDB${PREV_NUMBER} -i${SYBCFG_FILE}
}
help()
{
  head -10 $0 | tail -31
  exit
}

log (){
  echo -ne "[`date '+%d%m%Y %T'`] $1" | tee -a ${LAST}
}

# Check if $1 is equal to 0. If so print out message specified in $2 and exit.
check_empty() {
    if [ $1 -eq 0 ]; then
        echo $2
        exit 1
    fi
}

# Check if $1 is an object and if it has an 'errorMessage' specified. If so, print the object and exit.
check_error() {
    # ${JQ} returns a literal null so we have to check againt that...
    if [ "$(echo "$1" | ${JQ} -r 'if type=="object" then .errorMessage else "null" end')" != 'null' ]; then
        echo $1
        exit 1
    fi
}

# Login and set the correct $AUTH_HEADER.
login() {
echo "* Creando sesion..."
SES_RESPONSE=$($CURL -s -X POST -k --data @- $DELPHIX_ENGINE/session -c ./cookies.txt -H 'Content-Type: application/json' <<EOF
{
   "type": "APISession",
   "version": {
       "type": "APIVersion",
       "major": 1,
       "minor": 4,
       "micro": 3
   }
}
EOF
)

#echo $SES_RESPONSE
check_error "$SES_RESPONSE"

echo "* Login..."

LOGIN_RESPONSE=$($CURL -s -X POST -k --data @- $DELPHIX_ENGINE/login -b ./cookies.txt -c ./cookies2.txt -H 'Content-Type: application/json' <<EOF
{
"type": "LoginRequest",
"username": "admin",
"password": "delphix",
"target": "DOMAIN"
}
EOF
)
#echo $LOGIN_RESPONSE
check_error "$LOGIN_RESPONSE"

echo "* Login Completo..."
}
get_repository(){

STATUS=`$CURL -s -X GET -k ${DELPHIX_ENGINE}/repository -b ./cookies2.txt -H 'Content-Type: application/json'`

REPOSITORY_REF=`echo "${STATUS}" | ./bin/jq --raw-output '.result[] | select (.environment=="UNIX_HOST_ENVIRONMENT-4" and .name=="'DB"${PREV_NUMBER}"'") | .reference '`
#echo "* Repository name: "$REPOSITORY_REF
}
refresh_environment(){
 echo "* Refrescando environment..."
 $CURL -X POST $DELPHIX_ENGINE/environment/UNIX_HOST_ENVIRONMENT-4/refresh -H 'Content-Type: application/json' -b ./cookies2.txt
}

add_vdbs(){
echo "* Agregando Vdbs..."
json_db1="{
\"sourceConfig\": {
    \"instance\": {
        \"host\": \"UNIX_HOST-3\",
        \"type\": \"ASEInstanceConfig\"
    },
    \"databaseName\": \"db1\",
    \"type\": \"ASESIConfig\",
    \"environmentUser\": \"HOST_USER-4\",
    \"repository\": \"${REPOSITORY_REF}\"
    },
\"container\": {
    \"group\": \"GROUP-3\",
    \"type\": \"ASEDBContainer\",
    \"name\": \"vdb1_${PREV_NUMBER}\"
    },
\"truncateLogOnCheckpoint\": true,
\"source\": {
    \"allowAutoVDBRestartOnHostReboot\": false,
    \"type\": \"ASEVirtualSource\",
    \"name\": \"db1\"
  }, 
\"timeflowPointParameters\": {
  \"type\": \"TimeflowPointSemantic\", 
  \"location\": \"LATEST_POINT\",
  \"container\": \"ASE_DB_CONTAINER-1\"
  }, 
\"type\": \"ASEProvisionParameters\"
}"
json_db2="{
\"sourceConfig\": {
    \"instance\": {
        \"host\": \"UNIX_HOST-3\",
        \"type\": \"ASEInstanceConfig\"
    },
    \"databaseName\": \"db2\",
    \"type\": \"ASESIConfig\",
    \"environmentUser\": \"HOST_USER-4\",
    \"repository\": \"${REPOSITORY_REF}\"
    },
\"container\": {
    \"group\": \"GROUP-3\",
    \"type\": \"ASEDBContainer\",
    \"name\": \"vdb2_${PREV_NUMBER}\"
    },
\"truncateLogOnCheckpoint\": true,
\"source\": {
    \"allowAutoVDBRestartOnHostReboot\": false,
    \"type\": \"ASEVirtualSource\",
    \"name\": \"db2\"
  }, 
\"timeflowPointParameters\": {
  \"type\": \"TimeflowPointSemantic\", 
  \"location\": \"LATEST_POINT\",
  \"container\": \"ASE_DB_CONTAINER-2\"
  }, 
\"type\": \"ASEProvisionParameters\"
}"

ADD_DB1=$($CURL -s -X POST -k --data @- $DELPHIX_ENGINE/database/provision -H 'Content-Type: application/json' -b ./cookies2.txt <<EOF
${json_db1}
EOF
)
check_error "$ADD_DB1"


ADD_DB2=$($CURL -s -X POST -k --data @- $DELPHIX_ENGINE/database/provision -H 'Content-Type: application/json' -b ./cookies2.txt <<EOF
${json_db2}
EOF
)
check_error "$ADD_DB2"

}
################################
# ARGPARSER                    #
################################
# Verifica si fue enviado algun parametro
[ $1 =="-h" ] || { help ; exit 1 ; }

# Verifica si ${JQ} esta 
if [ "$(uname -s)." == "Linux." ] 
  then 
    JQ="./bin/jq"
elif [ "$(uname -s)." == "Darwin." ] 
  then
    JQ="./bin/jq-osx"
fi
    
[ -x "${JQ}" ] || { echo "jq not found. Please install 'jq' package and try again." ; exit 1 ; }

################################
# MAIN                         #
################################
if [ ${DELPHIX_ENGINE} ]
then
    # Login
    login
    echo -n "Press [ENTER] to continue,...: "
    read var_name
    # Create sybase instance
    buildSybase
    echo -n "Press [ENTER] to continue,...: "
    read var_name
    # Refresh Entorno
    refresh_environment
    echo -n "Press [ENTER] to continue,...: "
    read var_name
    # Get Repository Ref
    get_repository
    echo -n "Press [ENTER] to continue,...: "
    read var_name
    # Agrega vdbs
    add_vdbs
    echo -n "Press [ENTER] to continue,...: "
    read var_name
fi
