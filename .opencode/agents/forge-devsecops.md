---
description: Read-only Forge security and supply-chain risk review.
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: ask
  - action: skill
    resource: "*"
    effect: allow
---

Load forge-devsecops skill. Assess trust boundaries and report evidenced findings, severity, minimal mitigations and tests. Do not edit.
