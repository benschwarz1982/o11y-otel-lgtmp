variable "resource_group_name" {
  type        = string
  description = "Name of the (already existing) Azure Resource Group, see terraform/environments/demo/variables.tf"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the already-existing AKS cluster (created by terraform/environments/demo)"
  default     = "aks-otel-demo"
}

variable "dns_zone_name" {
  type        = string
  description = "Name of the already existing Azure DNS subdomain zone (see README section A2) - openclaw.<this> gets its own A record/Certificate/IngressRoute, same pattern as Grafana's in observability-stack."
}

variable "cert_manager_client_id" {
  type        = string
  description = "App ID of the cert-manager Service Principal (README section A6). Empty string skips OpenClaw's Certificate/IngressRoute/DNS record entirely, same guard observability-stack-crs uses for Grafana's - the ClusterIssuer they'd reference doesn't exist without it."
  default     = ""
}

variable "anthropic_setup_token" {
  type        = string
  description = "Claude subscription setup-token (`claude setup-token`, README A7) - OpenClaw's built-in anthropic provider bills it against the Claude Pro/Max subscription's own usage allowance, not per-token API billing. Empty string until set - OpenClaw then simply has no working model provider, same empty-string-skips-it guard pattern as observability-stack's cert_manager_client_id/secret."
  default     = ""
  sensitive   = true
}

variable "openclaw_model" {
  type        = string
  description = "Default model of OpenClaw's agent, as <provider>/<model id> from the image's own catalog (`openclaw models list --all --provider anthropic`)."
  default     = "anthropic/claude-sonnet-5"
}

variable "openclaw_gateway_token" {
  type        = string
  description = "Shared secret between Grafana's webhook contact point (terraform/environments/tenants) and OpenClaw's own gateway auth. Must be set to the same value in both Terraform states' CI/CD variables."
  default     = ""
  sensitive   = true
}

variable "openclaw_hooks_token" {
  type        = string
  description = "Shared secret for OpenClaw's dedicated gateway.hooks.* HTTP endpoint (/hooks/agent), separate from openclaw_gateway_token. Grafana's webhook contact point (terraform/environments/tenants) uses this endpoint instead of /v1/chat/completions because it responds asynchronously (returns on admission, not on full agent completion) - found live: the synchronous chat-completions endpoint made Grafana's own webhook HTTP client time out once the agent actually started reading runbooks/executing tools, well before OpenClaw finished responding. Must be set to the same value in both Terraform states' CI/CD variables."
  default     = ""
  sensitive   = true
}

variable "openclaw_agent_name" {
  type        = string
  description = "Display name of the OpenClaw agent, injected into openclaw/workspace-templates/IDENTITY.md."
  default     = "Claw"
}

variable "openclaw_organisation_name" {
  type        = string
  description = "Organisation name injected into openclaw/workspace-templates/{AGENTS,IDENTITY,USER}.md."
  default     = "observability-otel-demo"
}

variable "openclaw_operator_name" {
  type        = string
  description = "Primary operator name injected into openclaw/workspace-templates/USER.md."
  default     = "SRE Team"
}
