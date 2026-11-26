# Read by the instrumentation-4711-mitarbeiterverzeichnis/
# instrumentation-4722-spesenabrechnung CI jobs
# (`terraform output -raw pyroscope_internal_ip`, read-only, against this
# state) for the continuous-profiling agent config (see B12 in the main
# README). Points at the Pyroscope ingest proxy (Basic Auth per tenant),
# not at Pyroscope itself. 4721 Kundenverwaltung doesn't need this: it's
# K8s-native and pushes to the proxy's in-cluster Service
# (pyroscope-ingest.observability.svc.cluster.local).
# A LoadBalancer Service already blocks this environment's own apply
# until it gets its IP (wait_for_load_balancer, the provider's default),
# so the value is stable in state once deploy:observability-stack is
# done - no polling needed.
output "pyroscope_internal_ip" {
  value = kubernetes_service_v1.pyroscope_internal.status[0].load_balancer[0].ingress[0].ip
}

# NFR-04 mTLS - read by every VM instrumentation job (1229, 1286, 4711,
# 4722) for `ansible-playbook -e traefik_otlp_ip=...`: the per-tenant
# SNI-routed mTLS entrypoint (kubernetes_service_v1.traefik_otlp_internal).
# The old unencrypted gateway_internal_ip:4317 path is gone (F03).
output "traefik_otlp_ip" {
  value = kubernetes_service_v1.traefik_otlp_internal.status[0].load_balancer[0].ingress[0].ip
}
