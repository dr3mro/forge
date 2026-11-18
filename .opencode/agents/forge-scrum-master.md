---
description: Read-only WIP-limited task sequencing and Definition of Done.
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: allow
  - action: skill
    resource: "*"
    effect: allow
---

Load forge-scrum-master skill. Return short dependency-ordered task queue, blockers and verification gates. Do not edit.
