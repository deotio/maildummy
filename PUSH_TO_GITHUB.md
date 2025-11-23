# Push Maildummy Repository to GitHub

The maildummy repository needs to be pushed to GitHub before Terraform can use it as a git source.

## Quick Setup

```bash
cd /Users/rmyers/repos/dot/maildummy

# Check current status
git status

# If there are uncommitted changes, commit them
git add .
git commit -m "Add maildummy infrastructure module"

# Push to GitHub (the remote is already configured)
git push -u origin main
```

## Verify Push

After pushing, verify the repository is accessible:

```bash
# Check remote
git remote -v

# Verify push was successful
git ls-remote origin
```

## Update Terraform Configuration

Once the repository is pushed and accessible, the current configuration in `environments/dev/terraform/main.tf` should work:

```hcl
module "ses_maildummy" {
  source = "git::ssh://git@github.com/deotio/maildummy.git//terraform/modules/ses_maildummy?ref=main"
  # ... rest of config
}
```

## Test the Configuration

After pushing, test that Terraform can access the module:

```bash
cd /Users/rmyers/repos/dot/skybber/skybber_at/environments/dev/terraform
terraform init -upgrade
```

If you get authentication errors, ensure:
1. Your SSH key is added to GitHub
2. You have access to the `deotio/maildummy` repository
3. The repository is not private (or use appropriate authentication)

## Alternative: Use HTTPS with Personal Access Token

If SSH doesn't work in your environment (e.g., Terraform Cloud), you can use HTTPS:

1. Create a GitHub Personal Access Token with `repo` scope
2. Update the source URL:
   ```hcl
   source = "git::https://<token>@github.com/deotio/maildummy.git//terraform/modules/ses_maildummy?ref=main"
   ```
   
   Or use Terraform's credential helper for better security.

