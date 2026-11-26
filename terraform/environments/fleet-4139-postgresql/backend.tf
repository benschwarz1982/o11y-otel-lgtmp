# State lives in an Azure Storage Account (Entra ID auth, no shared keys) -
# created once by bootstrap/bootstrap.sh. The account/container/key are
# passed at init time (ci/scripts/tf-init.sh), so the same code works
# for every environment. The GitLab pipeline swaps this block for its own
# HTTP state backend via ci/gitlab/http-backend-override.sh.
terraform {
  backend "azurerm" {}
}
