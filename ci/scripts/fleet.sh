#!/usr/bin/env bash
# Provision, instrument or destroy one demo system.
#
#   ci/scripts/fleet.sh <system> <provision|instrument|destroy>
#
# provision  = the system without telemetry (deploy-fleets:* in GitLab)
# instrument = add the OTel collector/agent/SDK config (deploy-instrumentations:*)
# destroy    = tear it down (4711/4722 live on the 1286/1229 VMs and go with them)
set -euo pipefail

system="${1:?usage: fleet.sh <system> <provision|instrument|destroy>}"
action="${2:?usage: fleet.sh <system> <provision|instrument|destroy>}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
cd "${root}"

tf_env() { # <environment> <apply|destroy> [extra args...]
  local env_name="$1" verb="$2"; shift 2
  "${here}/tf-init.sh" "${env_name}"
  terraform -chdir="terraform/environments/${env_name}" "${verb}" -input=false -lock-timeout=5m -auto-approve "$@"
}

out() { # <environment> <output>
  terraform -chdir="terraform/environments/$1" output -raw "$2"
}

# Key material and scratch files: removed by ci/scripts/cleanup.sh
tmp="${RUNNER_TEMP:-/tmp}/otel-demo"
mkdir -p "${tmp}"

linux_inventory() {
  "${here}/tf-init.sh" fleet-1286-linux-basis >/dev/null
  out fleet-1286-linux-basis ssh_private_key > "${tmp}/vm-rocky-demo.pem"
  chmod 600 "${tmp}/vm-rocky-demo.pem"
  local ip user
  ip="$(out fleet-1286-linux-basis public_ip_address)"
  user="$(out fleet-1286-linux-basis admin_username)"
  echo "${ip} $(out fleet-1286-linux-basis ssh_host_public_key)" > "${tmp}/known_hosts"
  ROCKY_IP="${ip}"
  cat > ansible/inventory/generated.ini <<INI
[platform_linux]
vm-rocky-demo ansible_host=${ip} ansible_user=${user} ansible_ssh_private_key_file=${tmp}/vm-rocky-demo.pem ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=yes -o UserKnownHostsFile=${tmp}/known_hosts'
[platform_windows]
INI
}

windows_inventory() {
  "${here}/tf-init.sh" fleet-1229-windows-basis >/dev/null
  local ip user pass
  ip="$(out fleet-1229-windows-basis public_ip_address)"
  user="$(out fleet-1229-windows-basis admin_username)"
  pass="$(out fleet-1229-windows-basis admin_password)"
  # Never let the admin password reach the job log.
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::${pass}"
  out fleet-1229-windows-basis winrm_server_cert_pem > "${tmp}/winrm-server.pem"
  WINDOWS_IP="${ip}"
  cat > ansible/inventory/generated.ini <<INI
[platform_linux]
[platform_windows]
vm-windows-demo ansible_host=${ip} ansible_user=${user} ansible_password=${pass} ansible_connection=winrm ansible_winrm_transport=basic ansible_winrm_server_cert_validation=validate ansible_winrm_ca_trust_path=${tmp}/winrm-server.pem ansible_port=5986
INI
}

stack_ips() { # [pyroscope] - the middleware playbooks also need Pyroscope
  "${here}/tf-init.sh" observability-stack >/dev/null
  TRAEFIK_OTLP_IP="$(out observability-stack traefik_otlp_ip)"
  echo "Traefik OTLP mTLS internal IP: ${TRAEFIK_OTLP_IP}"
  if [ "${1:-}" = pyroscope ]; then
    PYROSCOPE_IP="$(out observability-stack pyroscope_internal_ip)"
    echo "Pyroscope internal IP: ${PYROSCOPE_IP}"
  fi
}

playbook() { # <playbook> [args...]
  # ansible.cfg is ignored in a world-writable directory (checkout umask)
  chmod o-w ansible
  (
    cd ansible
    export ANSIBLE_HOST_KEY_CHECKING=True ANSIBLE_ROLES_PATH="${PWD}/roles"
    ansible-playbook -i inventory/generated.ini "playbooks/$1" "${@:2}"
  )
}

open_8080() { # <nsg> <rule-name>
  az network nsg rule create -g "${AZURE_RESOURCE_GROUP:?}" --nsg-name "$1" --name "$2" \
    --priority 200 --access Allow --direction Inbound --destination-port-ranges 8080 --protocol Tcp \
    --only-show-errors -o none
}

# instrument=false/true toggle for the Terraform-only systems
tf_toggle() { # <environment>
  case "${action}" in
    provision)  tf_env "$1" apply -var instrument=false ;;
    instrument) tf_env "$1" apply -var instrument=true ;;
    destroy)    tf_env "$1" destroy ;;
  esac
}

case "${system}:${action}" in
  1229-windows-basis:provision)  tf_env fleet-1229-windows-basis apply ;;
  1229-windows-basis:destroy)    tf_env fleet-1229-windows-basis destroy ;;
  1229-windows-basis:instrument)
    windows_inventory; stack_ips
    playbook onboard-platform-windows.yml -e "traefik_otlp_ip=${TRAEFIK_OTLP_IP} tenant_id=1229-prod deployment_environment=prod"
    ;;

  1286-linux-basis:provision)    tf_env fleet-1286-linux-basis apply ;;
  1286-linux-basis:destroy)      tf_env fleet-1286-linux-basis destroy ;;
  1286-linux-basis:instrument)
    linux_inventory; stack_ips
    playbook onboard-platform-linux.yml -e "traefik_otlp_ip=${TRAEFIK_OTLP_IP} tenant_id=1286-prod deployment_environment=prod"
    ;;

  1294-netzwerk-basis:*)         tf_toggle fleet-1294-netzwerk-basis ;;
  4015-filestorage:*)            tf_toggle fleet-4015-filestorage ;;
  4720-otel-astronomy-shop:*)    tf_toggle fleet-4720-otel-astronomy-shop ;;

  4721-kundenverwaltung:provision)
    # Re-provisioning must not switch telemetry off again: keep whatever
    # the current state has (PostgreSQL collector present = instrumented).
    "${here}/tf-init.sh" fleet-4139-postgresql
    if ! resources="$(terraform -chdir=terraform/environments/fleet-4139-postgresql state list 2>"${tmp}/state-list.err")"; then
      grep -q 'No state file was found' "${tmp}/state-list.err" || { cat "${tmp}/state-list.err"; exit 1; }
      resources=""
    fi
    instrument=false
    printf '%s\n' "${resources}" | grep -q '^kubernetes_manifest\.postgres_otel_collector' && instrument=true
    echo "instrument=${instrument} (kept from current state)"
    tf_env fleet-4139-postgresql apply -var "instrument=${instrument}"
    ;;
  4721-kundenverwaltung:instrument) tf_env fleet-4139-postgresql apply -var instrument=true ;;
  4721-kundenverwaltung:destroy)    tf_env fleet-4139-postgresql destroy ;;

  4711-mitarbeiterverzeichnis:provision)
    linux_inventory
    playbook onboard-middleware-tomcat.yml --tags install
    open_8080 vm-rocky-demoNSG AllowTomcat8080Inbound
    echo "4711 provisioned on vm-rocky-demo (no telemetry yet) - http://${ROCKY_IP}:8080/examples/servlets/servlet/HelloWorldExample"
    ;;
  4711-mitarbeiterverzeichnis:instrument)
    linux_inventory; stack_ips pyroscope
    playbook onboard-middleware-tomcat.yml --tags instrument -e "traefik_otlp_ip=${TRAEFIK_OTLP_IP} pyroscope_internal_ip=${PYROSCOPE_IP} tenant_id=4711-prod service_name=tomcat-demo-app service_namespace=mitarbeiterverzeichnis deployment_environment=prod app_owner='Web App Team' app_cost_center=CC-4711 app_size_class=M"
    ;;

  4722-spesenabrechnung:provision)
    windows_inventory
    playbook onboard-middleware-dotnet.yml --tags install
    open_8080 vm-windows-demoNSG AllowSpesenabrechnung8080Inbound
    echo "4722 provisioned (no telemetry yet) - http://${WINDOWS_IP}:8080/"
    ;;
  4722-spesenabrechnung:instrument)
    windows_inventory; stack_ips pyroscope
    playbook onboard-middleware-dotnet.yml --tags instrument -e "traefik_otlp_ip=${TRAEFIK_OTLP_IP} pyroscope_internal_ip=${PYROSCOPE_IP} tenant_id=4722-prod service_namespace=spesenabrechnung deployment_environment=prod app_owner='Platform Engineering' app_cost_center=CC-4722 app_size_class=S"
    ;;

  4711-mitarbeiterverzeichnis:destroy|4722-spesenabrechnung:destroy)
    echo "${system} runs on a fleet VM and is removed together with it - nothing to do."
    ;;
  *)
    echo "Unknown system/action: ${system} ${action}" >&2
    exit 1
    ;;
esac
