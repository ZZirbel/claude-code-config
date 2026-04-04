# Windows Refactoring Assessment

## Executive Summary

This document assesses the work required to bring the Windows fork (`ZZirbel/claude-code-config`) up to parity with the upstream (`aaronsb/claude-code-config`) while maintaining full Windows/PowerShell support.

**Key Finding**: The architectures are fundamentally compatible. Both use:
- C-based `way-match` binary (BM25 matching via Cosmopolitan APE)
- Shell scripts for hook orchestration
- Same way.md frontmatter format
- Same marker-based idempotency system

The upstream has evolved with more features, more ways, and better testing—but the core architecture remains the same. Your Windows PowerShell ports remain valid; they just need updating to match upstream script changes.

---

## Architecture Comparison

| Component | Your Fork (Windows) | Upstream (aaronsb) | Delta |
|-----------|--------------------|--------------------|-------|
| **Matching Engine** | `way-match` (C/APE) | `way-match` (C/APE) | Same |
| **Hook Orchestration** | Bash + PowerShell | Bash only | You're ahead |
| **Settings Config** | `settings.json` + `settings.windows.json` | `settings.json` only | You're ahead |
| **Way Count** | ~30 ways | **85+ ways** | Behind |
| **Domains** | softwaredev, meta, itops | **+ea (10), +research (1), +writing (1)** | Behind |
| **Re-disclosure** | Not present | `redisclose:` field | Behind |
| **Per-agent Markers** | Basic | Enhanced tracking | Behind |
| **Multilingual** | Not present | 18 languages | Behind |
| **Testing** | Manual | 8-scenario simulator | Behind |
| **Status Line** | `statusline.sh` + `statusline.ps1` | `statusline.sh` only | You're ahead |

---

## Refactoring Categories

### Category 1: Binary Compatibility (LOW EFFORT)

The `way-match` binary is built with Cosmopolitan as an APE (Actually Portable Executable). This **should** run on Windows natively.

**Current State**:
- Binary exists at `bin/way-match` (61KB APE)
- PowerShell scripts look for `way-match.exe` in `match-way.ps1`

**Refactoring Required**:
1. Test if APE binary runs on Windows directly
2. If not, either:
   - Rename `way-match` → `way-match.exe` (APE may need extension)
   - Cross-compile with `cosmocc` targeting Windows
   - Build native Windows binary with MSVC/MinGW

**Validation**:
```powershell
# Test binary execution
& "$env:USERPROFILE\.claude\bin\way-match" pair `
  --description "test" --vocabulary "test" `
  --query "test" --threshold 1.0
echo $LASTEXITCODE  # Should be 0
```

---

### Category 2: New Ways & Domains (MEDIUM EFFORT)

Upstream has added 50+ new ways across expanded domains.

**New Domains to Add**:
| Domain | Ways | Purpose |
|--------|------|---------|
| `ea/` | 10 | Executive Assistant workflows |
| `research/` | 1 | Research methodologies |
| `writing/` | 1 | Documentation & content |

**Updated Domains**:
| Domain | Changes |
|--------|---------|
| `softwaredev/` | New ways: visualization, more architecture patterns |
| `meta/` | New ways: project-health, think, todos, trust |

**Refactoring Required**:
1. Pull all new `way.md` files from upstream
2. Review for any bash-specific macros that need PowerShell equivalents
3. Test pattern/semantic matching on Windows

**No Script Changes Needed**: Ways are data files (YAML+Markdown), not executables.

---

### Category 3: Hook Script Updates (MEDIUM-HIGH EFFORT)

Upstream has refined several hook scripts. Your PowerShell ports need updating.

**Scripts Requiring Review**:

| Bash Script | PS1 Equivalent | Changes Needed |
|-------------|----------------|----------------|
| `check-prompt.sh` | `check-prompt.ps1` | Sync logic updates |
| `check-state.sh` | `check-state.ps1` | New state triggers |
| `check-bash-pre.sh` | `check-bash-pre.ps1` | Minor updates |
| `check-file-pre.sh` | `check-file-pre.ps1` | Minor updates |
| `check-task-pre.sh` | `check-task-pre.ps1` | Enhanced stashing |
| `inject-subagent.sh` | `inject-subagent.ps1` | Per-agent markers |
| `show-way.sh` | `show-way.ps1` | Re-disclosure support |
| `match-way.sh` | `match-way.ps1` | Threshold tuning |
| `macro.sh` | `macro.ps1` | Table generation updates |
| `show-core.sh` | `show-core.ps1` | Core guidance updates |
| `check-config-updates.sh` | `check-config-updates.ps1` | Detection improvements |

**New Scripts (Need PS1 Equivalents)**:
- `check-setup.sh` → `check-setup.ps1` (validates prerequisites)
- `sessions-root.sh` → `sessions-root.ps1` (session directory config)
- `require-ways.sh` → `require-ways.ps1` (ways requirement checker)

**Refactoring Strategy**:
1. Diff each bash script against your current version
2. Identify logic changes vs cosmetic changes
3. Port logic changes to PowerShell equivalent
4. Test each hook individually

---

### Category 4: New Features (HIGH EFFORT)

Features that don't exist in your fork and require new implementation.

#### 4.1 Re-disclosure System
**Purpose**: Allow ways to re-fire based on context window position.

**Implementation**:
- New frontmatter field: `redisclose: true|false`
- Marker system modification: Check context % before skipping
- Affects: `show-way.sh` / `show-way.ps1`

#### 4.2 Per-Agent Marker Tracking
**Purpose**: Prevent subagent marker collisions.

**Implementation**:
- Marker naming: Include agent ID in marker path
- Affects: `show-way.sh`, `inject-subagent.sh`, `check-task-pre.sh`

#### 4.3 Context-Threshold Auto-Nag
**Purpose**: Remind about task creation before compaction.

**Implementation**:
- `check-state.sh` evaluates transcript size %
- `repeat: true` field enables continuous firing
- `tasks-active` marker stops nagging

#### 4.4 Session Simulator Testing
**Purpose**: Automated hook flow testing.

**Implementation**:
- 8 test scenarios exercising full hook pipeline
- Would need PowerShell test harness for Windows validation

---

### Category 5: Path & Environment Handling (LOW-MEDIUM EFFORT)

Windows-specific path handling improvements needed.

**Current Issues**:
| Issue | Current Behavior | Required Fix |
|-------|------------------|--------------|
| Temp directory | Hardcoded `/tmp/` in some places | Use `$env:TEMP` consistently |
| Home directory | Mix of `$HOME` and `$env:USERPROFILE` | Standardize to `$env:USERPROFILE` |
| Path separators | Some scripts output `/` paths | Normalize or handle both |
| Binary extension | Looking for `way-match.exe` | Handle APE naming |

**Refactoring Required**:
1. Audit all PowerShell scripts for path handling
2. Create shared path resolution functions
3. Test on both `C:\Users\...` and WSL paths

---

### Category 6: Build & Installation (MEDIUM EFFORT)

Upstream has enhanced the installation process.

**Current Upstream Capabilities**:
```bash
make setup    # Build binary, download model, generate corpus
make install  # Full setup + PATH symlink
make update   # Pull + reinstall
make test     # Full test suite
```

**Windows Needs**:
1. `setup.ps1` or `Makefile` with PowerShell targets
2. Binary verification (SHA-256 checksums)
3. Settings file selection (`settings.json` vs `settings.windows.json`)
4. PATH modification for `way-match.exe`

**Proposed Windows Installation**:
```powershell
# setup.ps1
param([switch]$Auto)

# 1. Copy settings.windows.json → settings.json (or symlink)
# 2. Verify/download way-match binary
# 3. Test binary execution
# 4. Run hook smoke tests
# 5. Display success message
```

---

## Refactoring Prioritization

### Phase 1: Foundation (Required for basic functionality)

| Task | Effort | Impact |
|------|--------|--------|
| Verify/fix `way-match` binary on Windows | Low | Critical |
| Sync `settings.windows.json` hook definitions | Low | Critical |
| Update `match-way.ps1` for binary invocation | Low | Critical |
| Pull new ways (data files only) | Low | High |

**Estimated Effort**: 2-4 hours

### Phase 2: Core Hook Parity (Required for full functionality)

| Task | Effort | Impact |
|------|--------|--------|
| Port `check-setup.sh` → `check-setup.ps1` | Medium | High |
| Update `check-prompt.ps1` with upstream changes | Medium | High |
| Update `show-way.ps1` for re-disclosure | Medium | Medium |
| Update `inject-subagent.ps1` for per-agent markers | Medium | Medium |
| Port `sessions-root.sh` → `sessions-root.ps1` | Low | Medium |

**Estimated Effort**: 4-8 hours

### Phase 3: Feature Parity (Nice to have)

| Task | Effort | Impact |
|------|--------|--------|
| Implement context-threshold auto-nag | High | Medium |
| Create Windows test harness | High | Medium |
| Add multilingual support | High | Low |
| Create `setup.ps1` installer | Medium | Medium |

**Estimated Effort**: 8-16 hours

### Phase 4: Maintenance Infrastructure (Long-term)

| Task | Effort | Impact |
|------|--------|--------|
| CI/CD for Windows testing | High | High |
| Automated upstream sync detection | Medium | Medium |
| PowerShell Pester test suite | High | Medium |

**Estimated Effort**: 16+ hours

---

## Detailed Script Comparison

### check-prompt.sh Changes

**Upstream additions**:
1. Response topic integration (from `check-response.sh`)
2. Enhanced scope detection
3. Threshold tuning (2.0 → configurable)

**PowerShell port required**:
```powershell
# Add to check-prompt.ps1
$responseTopics = Get-Content "$env:TEMP\claude-response-topics-$sessionId" -ErrorAction SilentlyContinue
$combinedPrompt = "$prompt $responseTopics"
```

### show-way.sh Changes

**Upstream additions**:
1. `redisclose:` field support
2. Per-agent marker naming
3. Enhanced logging

**PowerShell port required**:
```powershell
# Add re-disclosure check
$redisclose = Get-YamlField $wayPath "redisclose"
if ($redisclose -eq "true") {
    # Check context window % before skipping
}
```

### inject-subagent.sh Changes

**Upstream additions**:
1. FIFO stash consumption for parallel tasks
2. Per-agent marker creation
3. Enhanced teammate detection

**PowerShell port complexity**: Medium-High (FIFO semantics tricky in PowerShell)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| APE binary doesn't run on Windows | Low | Critical | Build native Windows binary |
| PowerShell execution policy blocks hooks | Medium | High | Document `-ExecutionPolicy Bypass` |
| Path handling breaks on non-C: drives | Medium | Medium | Use `$PWD` and relative paths |
| Git Bash interference with native PS | Low | Medium | Ensure PS scripts don't invoke bash |
| Upstream breaking changes | Medium | High | Pin to specific upstream commit |

---

## Recommended Approach

### Option A: Incremental Sync (Recommended)

1. **Create a sync branch**: `git checkout -b upstream-sync`
2. **Add upstream remote**: `git remote add upstream https://github.com/aaronsb/claude-code-config`
3. **Fetch upstream**: `git fetch upstream`
4. **Cherry-pick data files**: Ways, docs, governance (no conflicts expected)
5. **Review script changes**: Diff each bash script, port changes to PS1
6. **Test incrementally**: Validate each hook before proceeding
7. **Merge when stable**: `git checkout main && git merge upstream-sync`

### Option B: Full Replacement + Re-port

1. **Backup current PowerShell scripts**
2. **Replace with upstream main**
3. **Re-port all PowerShell scripts from scratch**
4. **Benefit**: Cleaner codebase, full feature parity
5. **Risk**: Higher effort, potential regression

### Option C: Maintain Separate Fork

1. **Keep current Windows-focused fork**
2. **Selectively pull upstream features**
3. **Accept permanent drift from upstream**
4. **Benefit**: Full control, Windows-first
5. **Risk**: Maintenance burden, missing features

---

## Automation Opportunity

Once refactoring is complete, create a `pc-refactor.md` instruction file that Claude Code can execute automatically when pulling upstream changes:

```markdown
# PC Refactor Instructions

When pulling changes from upstream (aaronsb/claude-code-config):

1. **Binary Check**: Verify `bin/way-match` runs on Windows
2. **Settings Sync**: Merge new hooks into `settings.windows.json`
3. **Script Diff**: For each changed `.sh` file, update corresponding `.ps1`
4. **Way Sync**: Copy new `way.md` files (no changes needed)
5. **Test**: Run hook smoke tests

## Automatic Transformations

### Path Conversions
- `$HOME` → `$env:USERPROFILE`
- `/tmp/` → `$env:TEMP\`
- `~/.claude/` → `$env:USERPROFILE\.claude\`

### Command Conversions
- `jq` → `ConvertFrom-Json` / `ConvertTo-Json`
- `grep` → `Select-String`
- `sed` → `-replace` operator
- `awk` → PowerShell string manipulation
```

---

## Conclusion

The refactoring is **achievable and well-scoped**. The core architecture is identical between forks—only the execution layer (bash vs PowerShell) differs.

**Immediate priorities**:
1. Verify APE binary Windows compatibility
2. Pull new ways (zero-effort content sync)
3. Update PowerShell hooks incrementally

**Long-term investment**:
1. Create automated sync tooling
2. Contribute Windows support back to upstream
3. Establish Windows CI/CD testing

The work is primarily **porting** (translating bash → PowerShell) rather than **redesigning**. Your existing PowerShell infrastructure provides a solid foundation.
