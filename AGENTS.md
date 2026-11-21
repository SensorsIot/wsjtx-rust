# Working in this repository

The main session is the coordinator: load the `harness-coordinator` skill first
(installed with `install_skills.py --skill coordinator`, [agent roles](harness/general/core/agents/roles.md)).
Its handoff is the [project memory](harness/project/docs/MEMORY.md).

Product changes follow the [CR process](harness/general/core/docs/CR-Process.md); changes to how
the project is built, tested or gated follow [Harness changes](harness/general/core/docs/Harness-Changes.md).
The constraints a change must respect are indexed in the
[Harness Overview](harness/project/docs/Harness-Overview.md). Read only the parts relevant
to the task. The product contract's authority is bound in
[exclusive functional authority](harness/project/docs/specifics/product-model-maintenance.md#exclusive-functional-authority).

Agent workflows and project-local skill setup are indexed in the pinned
[harness skill](harness/general/SKILL.md) and [agent discovery](harness/general/README.md#agent-discovery).
The general harness is the git submodule at `harness/general/`
(https://github.com/SensorsIot/harness, branch `main`); the project harness is `harness/project/`.

Once per clone, the operator sets the checkout up
([Local Windows development](harness/project/docs/specifics/local-windows-development.md#local-windows-development)).
