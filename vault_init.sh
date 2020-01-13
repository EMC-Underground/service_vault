#!/bin/ash

success() {
    if [ $? -eq 0 ]
    then
      echo "DONE"
    else
      echo "ERROR"
        exit 1
    fi
}

vault_init() {
    printf "Initializing Vault.... "
    local  __resultvar=$1
    local i=0
    local o=0
    while [[ $i -lt 1 ]]
    do
        vault operator init -address=$vault_address -status > /dev/null 2>&1
        if [[ $? -eq 2 || $? -eq 0 ]]
        then
            ((i=i+1))
        else
            if [ $o -eq 4 ]
            then
                success
                ((i=i+1))
            else
                ((o=o+1))
                sleep 2
            fi
        fi
    done
    local result=`vault operator init -address=$vault_address -key-threshold=1 -key-shares=1 -format=json`
    success
    eval $__resultvar="'$result'"
}

vault_unseal() {
    local root_token=$1
    printf "Unsealing the vault.... "
    vault operator unseal -address=$vault_address $root_token > /dev/null 2>&1
    success
}

vault_create_store() {
    printf "Creating vault secret store.... "
    vault secrets enable -address=$vault_address -version=1 -path=concourse kv > /dev/null 2>&1
    success
}

vault_create_policy() {
    printf "Create vault policy.... "
    echo 'path "concourse/*" {
  policy = "read"
}' > /tmp/concourse-policy.hcl
    vault policy write -address=$vault_address concourse /tmp/concourse-policy.hcl > /dev/null 2>&1
    success
}

vault_create_token() {
    printf "Create vault service account.... "
    local __resultvar=$1
    local result=`vault token create -address=$vault_address -display-name=concourse -format=json --policy concourse --period 1hr | jq -r .auth.client_token`
    success
    eval $__resultvar="'$result'"
}

vault_login() {
    local root_token=$1
    printf "Logging into Vault.... "
    local i=0
    local o=0
    while [[ $i -lt 1 ]]
    do
        local ha_mode=`vault status -address=$vault_address | grep "HA Mode" | awk '{print $3}'`
        if [ $ha_mode == "active" ]
        then
            ((i=i+1))
        else
            if [ $o -eq 4 ]
            then
                success
            else
                ((o=o+1))
                sleep 2
            fi
        fi
    done
    vault login -address=$vault_address $root_token > /dev/null
    success
}

create_vault_secret() {
    local team=$1 pipeline=$2 secret=$3
    printf "Creating ${2} vault secret.... "
    echo -n "$secret" | vault kv put -address=$vault_address $team$pipeline value=- > /dev/null
    success
}

main() {
    echo "vault_init"
    vault_init keys
    unseal=`echo $keys | jq -r .unseal_keys_b64[0]`
    roottoken=`echo $keys | jq -r .root_token`
    echo "vault_unseal"
    vault_unseal $unseal
    vault_login $roottoken
    vault_create_store
    vault_create_policy
    vault_create_token concoursetoken
    export VAULT_CLIENT_TOKEN=$concoursetoken
    create_vault_secret "concourse/vault/" "unseal_token" $unseal
    create_vault_secret "concourse/vault/" "root_token" $roottoken
    create_vault_secret "concourse/vault/" "concourse_token" $concoursetoken
}

vault_address="http://vault.${DNS_SUFFIX}"
main
