<!--
Thanks for the change! Keep this small and focused — one decision per PR is
ideal. If this PR touches both Terraform and Helm, prefer two separate PRs
unless the change genuinely cannot be split.
-->

## What does this change?

<!-- One-line summary. -->

## Why?

<!-- Link to a rubric requirement, an entry in docs/decisions.md, an issue,
     or a runbook. If this is a new decision, also update docs/decisions.md
     in this PR. -->

## How to verify

<!--
For Terraform changes:
  - Paste the relevant `terraform plan` output below in a collapsible block.
  - Note any resources being destroyed or replaced.

For Helm / values changes:
  - `helm template` output snippet showing the change, OR
  - The rendered diff from a deployed environment.

For workflow changes:
  - Link to a successful run in a feature branch.
-->

## Risk and rollback

<!--
- Blast radius: which environments / users could this affect if wrong?
- How do we roll back? (e.g. revert this commit, re-apply previous values
  file, flip blue/green back, terraform state rollback to N-1.)
-->

## Checklist

- [ ] `terraform fmt -recursive` and `terraform validate` pass
- [ ] If a decision changed, `docs/decisions.md` is updated in this PR
- [ ] If deploy behaviour changed, the relevant runbook in `docs/runbooks/`
      is updated
- [ ] No secrets, kubeconfigs, or `.tfvars` files were committed
