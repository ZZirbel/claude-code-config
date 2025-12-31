# Ways System Architecture

Visual documentation of the ways trigger system.

## Hook Flow

How ways get triggered during a Claude Code session:

```mermaid
flowchart TB
    subgraph Session["Claude Code Session"]
        SS[SessionStart] --> Core["show-core.sh<br/>Dynamic table + core.md"]

        UP[UserPromptSubmit] --> CP["check-prompt.sh<br/>Scan keywords"]

        subgraph PostTool["PostToolUse"]
            Bash[Bash tool] --> CB["check-bash-post.sh<br/>Scan commands"]
            Edit[Edit/Write tool] --> CF["check-file-post.sh<br/>Scan file paths"]
        end
    end

    CP --> SW["show-way.sh"]
    CB --> SW
    CF --> SW

    SW --> Check{Marker exists?}
    Check -->|No| Output["Output way content<br/>Create marker"]
    Check -->|Yes| Silent["No-op (silent)"]
```

## Way State Machine

Each (way, session) pair has exactly two states:

```mermaid
stateDiagram-v2
    [*] --> NotShown: Session starts

    NotShown: not_shown
    NotShown: No marker file exists

    Shown: shown
    Shown: Marker file exists

    NotShown --> Shown: Keyword/command/file match<br/>→ Output + create marker
    Shown --> Shown: Any subsequent match<br/>→ No-op (idempotent)

    Shown --> [*]: Session ends<br/>(markers in /tmp auto-cleanup)
```

## Trigger Matching

How prompts and tool use get matched to ways:

```mermaid
flowchart LR
    subgraph Input
        Prompt["User prompt<br/>(lowercased)"]
        Cmd["Bash command"]
        File["File path"]
    end

    subgraph Scan["Recursive Scan"]
        Find["find */way.md"]
        Extract["Extract frontmatter:<br/>keywords, commands, files"]
    end

    subgraph Match["Regex Match"]
        KW["keywords: pattern"]
        CM["commands: pattern"]
        FL["files: pattern"]
    end

    Prompt --> Find
    Cmd --> Find
    File --> Find

    Find --> Extract
    Extract --> KW
    Extract --> CM
    Extract --> FL

    KW -->|match| SW["show-way.sh waypath session_id"]
    CM -->|match| SW
    FL -->|match| SW
```

## Macro Injection

Ways with `macro: prepend|append` run dynamic scripts:

```mermaid
sequenceDiagram
    participant Hook as check-*.sh
    participant Show as show-way.sh
    participant Macro as macro.sh
    participant Way as way.md
    participant Out as Output

    Hook->>Show: waypath, session_id
    Show->>Show: Check marker

    alt Marker exists
        Show-->>Hook: (silent return)
    else No marker
        Show->>Way: Read frontmatter

        alt macro: prepend
            Show->>Macro: Execute
            Macro-->>Out: Dynamic context
            Show->>Way: Strip frontmatter
            Way-->>Out: Static guidance
        else macro: append
            Show->>Way: Strip frontmatter
            Way-->>Out: Static guidance
            Show->>Macro: Execute
            Macro-->>Out: Dynamic context
        else no macro
            Show->>Way: Strip frontmatter
            Way-->>Out: Static guidance
        end

        Show->>Show: Create marker
    end
```

## Directory Structure

```mermaid
flowchart TB
    subgraph Global["~/.claude/hooks/ways/"]
        Core[core.md]
        Macro[macro.sh]
        ShowCore[show-core.sh]
        CheckP[check-prompt.sh]
        CheckB[check-bash-post.sh]
        CheckF[check-file-post.sh]
        ShowW[show-way.sh]

        subgraph Domain["softwaredev/"]
            subgraph WayDir["github/"]
                WayMD[way.md]
                WayMacro[macro.sh]
            end
            Other["adr/, commits/, ..."]
        end
    end

    subgraph Project["$PROJECT/.claude/ways/"]
        ProjDomain["{domain}/"]
        ProjWay["{wayname}/way.md"]
    end

    ProjWay -.->|overrides| WayMD
```

## Multi-Trigger Semantics

What happens when multiple triggers fire:

```mermaid
flowchart TB
    Prompt["'Let's review the PR and fix the bug'"]

    Prompt --> KW1["keywords: github|pr"]
    Prompt --> KW2["keywords: debug|bug"]
    Prompt --> KW3["keywords: review"]

    KW1 -->|match| GH["github way"]
    KW2 -->|match| DB["debugging way"]
    KW3 -->|match| QA["quality way"]

    GH --> M1{Marker?}
    DB --> M2{Marker?}
    QA --> M3{Marker?}

    M1 -->|No| O1["✓ Output github"]
    M2 -->|No| O2["✓ Output debugging"]
    M3 -->|No| O3["✓ Output quality"]

    M1 -->|Yes| S1["✗ Silent"]
    M2 -->|Yes| S2["✗ Silent"]
    M3 -->|Yes| S3["✗ Silent"]
```

Each way has its own marker - multiple ways can fire from one prompt, but each only fires once per session.

## Project-Local Override

```mermaid
flowchart TB
    subgraph Scan["Way Lookup Order"]
        P["1. Project: $PROJECT/.claude/ways/"]
        G["2. Global: ~/.claude/hooks/ways/"]
    end

    P -->|found| Use["Use project way"]
    P -->|not found| G
    G -->|found| UseG["Use global way"]
    G -->|not found| Skip["No match"]

    Use --> Mark["Single marker<br/>(by waypath)"]
    UseG --> Mark
```

Project ways take precedence. Only one marker per waypath regardless of source.
