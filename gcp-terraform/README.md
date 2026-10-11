# GCP Org Foundation — Terraform

Two stages, run in order:

```
bootstrap/    -> local state, run once, by an org admin
foundation/   -> remote (GCS) state, run by CI or the terraform-automation SA
modules/
  project-factory/  -> reusable module: one GCP project + APIs + IAM per call
```

## 1. One-time org-level grant (manual, by an Org Admin)

Terraform can't grant itself org-level permissions before it exists, so this
one step is manual (console or `gcloud`), done once:

```bash
gcloud organizations add-iam-policy-binding <ORG_ID> \
  --member="serviceAccount:<terraform-automation SA email>" \
  --role="roles/resourcemanager.folderAdmin"

gcloud organizations add-iam-policy-binding <ORG_ID> \
  --member="serviceAccount:<terraform-automation SA email>" \
  --role="roles/resourcemanager.projectCreator"

gcloud billing accounts add-iam-policy-binding <BILLING_ACCOUNT_ID> \
  --member="serviceAccount:<terraform-automation SA email>" \
  --role="roles/billing.user"
```

The SA doesn't exist yet on the very first run — so run `bootstrap/` first
under your own admin user credentials, THEN grant the SA the org-level roles
above, THEN switch `foundation/` (and everything after) to authenticate as
that SA.

## 2. Bootstrap

```bash
cd bootstrap
terraform init
terraform apply \
  -var="org_id=123456789012" \
  -var="billing_account=AAAAAA-BBBBBB-CCCCCC" \
  -var="project_id_prefix=myco"

terraform output state_bucket_name   # copy this into foundation/backend.tf
```

## 3. Foundation (folders + projects)

```bash
cd ../foundation
# edit backend.tf with the bucket name from step 2
cp terraform.tfvars.example terraform.tfvars   # edit with real values
terraform init
terraform plan
terraform apply
```

## Adding a new project later

Add a map entry to `terraform.tfvars` under `projects` — pick the
`folder_key` (`bootstrap` | `common` | `development` | `non_production` |
`production`), the APIs it needs, and apply. No new `.tf` files required.

## Design notes

- **Folders are flat, one level under the org.** This matches Google's own
  reference architecture and is enough for most orgs. If you later need
  per-team sub-folders inside an environment, add a second `google_folder`
  resource keyed off `google_folder.top[*].id` in `foundation/main.tf`.
- **`auto_create_network = false`** on every project — GCP's default VPC is a
  common source of accidental open-by-default networking; create VPCs
  explicitly per project or use a Shared VPC hosted from the `common`
  project.
- **State is split by stage**, not by environment. `bootstrap` almost never
  changes; `foundation` changes when folders/projects change. If your org
  grows large, consider splitting `foundation` further (e.g. one state per
  top-level folder) to reduce blast radius of a single `apply`.
- **Billing account per project is overridable** (`billing_account` field in
  the `projects` map) for cases like a sandboxed prod project that bills
  differently.
