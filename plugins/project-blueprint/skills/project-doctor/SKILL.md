---
name: project-doctor
description: Check a repo against the project blueprint and report every rule as pass, fail or N/A with evidence, then offer fixes.
disable-model-invocation: true
---

# Project doctor

Audit the current repo against [`../../blueprint/rules.md`](../../blueprint/rules.md). Read the matching language pack in [`../../blueprint/languages/`](../../blueprint/languages/) for the values the checks compare against.

## 1. Establish the facts

Language(s), kind (service, library, tool), whether the project uses the podman sandbox (SBX is N/A if not), GitHub visibility and trunk name (`gh repo view --json visibility,defaultBranchRef`), and the GitHub plan (ask: `gh` cannot read it). These decide which rules are N/A.

## 2. Check every rule

Run each rule's **Check** as written: read the file, run the command. A verdict needs evidence: a path and line, command output, or the reason it is N/A. "Looks fine" is not evidence.

Rules that need the user get **Ask**, with the question.

Done when every row of `rules.md` has a verdict and evidence. Count them.

## 3. Report

One table, in `rules.md` order, failures first within each area:

| ID | Verdict | Evidence | Fix |
|---|---|---|---|

The **Fix** column names the owner from `rules.md`. When the owner is another skill (`/mattpocock-skills:setup-matt-pocock-skills`, `podman-sandbox`, `wizard`, `/mattpocock-skills:grill-with-docs`, `/mattpocock-skills:retro`), the fix is "run that skill", not an edit you make in its place.

Below the table, list the three failures that matter most, by risk: a secret that could be committed, a deploy path that bypasses the trunk, prod credentials reachable from a dev deploy, or a fallback that sends a misconfigured service somewhere real outranks a missing README section.

## 4. Offer fixes

Ask which to fix. Make the fixes this plugin owns on a `chore/` branch, re-run their checks, and report each as fixed with the new evidence. Leave other skills' fixes to those skills.
