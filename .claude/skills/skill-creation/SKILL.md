---
name: skill-creation
description: Guidelines for creating and managing skills in this project. Use when adding, modifying, or reviewing skills in .claude/skills/.
---
# Creating and Managing Skills

This project uses the [Agent Skills](https://agentskills.io) format. Skills live in `.claude/skills/`.

## Directory Structure

Each skill is a directory containing at minimum a `SKILL.md` file. The directory name **must match** the `name` field in frontmatter.

```
.claude/skills/
  my-skill/
    SKILL.md
    scripts/       # Optional: executable code agents can run
    references/    # Optional: additional docs loaded on demand
    assets/        # Optional: templates, images, data files
```

## SKILL.md Format

### Frontmatter (required)

| Field           | Required | Description                                                                          |
| --------------- | -------- | ------------------------------------------------------------------------------------ |
| `name`          | Yes      | 1–64 chars. Lowercase alphanumeric + hyphens. No leading/trailing/consecutive `-`.   |
| `description`   | Yes      | 1–1024 chars. Describe what the skill does **and when to use it**.                   |


### Example

```markdown
---
name: my-skill
description: Standards for doing X in this project. Use when creating or modifying X.
---
# My Skill

Step-by-step instructions, examples, edge cases…
```

## Progressive Disclosure

Skills are loaded in stages to conserve context:

1. **Metadata** (~100 tokens) — `name` and `description` are loaded at startup for all skills.
2. **Instructions** (<5000 tokens recommended) — Full `SKILL.md` body loaded when activated.
3. **Resources** (as needed) — Files in `scripts/`, `references/`, `assets/` loaded on demand.

Keep `SKILL.md` under **500 lines**. Move detailed reference material to separate files using relative paths (one level deep).

## Registration

Skills must be registered in `AGENTS.md` under the Rules Index table so agents know when to consult them.

## Best Practices

1. **Focus**: One topic per skill (e.g., "Testing", "Styling").
2. **Actionable**: Concrete instructions, examples of inputs/outputs, edge cases.
3. **Naming**: Lowercase kebab-case directory names (e.g., `testing-standards/`).
4. **Description quality**: Include keywords that help agents match tasks. Describe *what* and *when*.
5. **Self-contained**: Each skill directory should contain everything the agent needs for that domain.
