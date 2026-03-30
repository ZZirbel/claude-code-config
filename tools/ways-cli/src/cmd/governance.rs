//! Governance operator — query provenance traceability for ways.
//!
//! Replaces: governance/governance.sh (543 lines)
//! Wraps the provenance manifest with auditor-friendly query modes:
//! report, trace, control, policy, gaps, stale, active, matrix, lint.

use anyhow::{bail, Result};
use serde_json::{json, Value};
use std::collections::HashMap;

use crate::cmd::provenance;

/// Governance query mode.
pub enum Mode {
    Report,
    Trace(String),
    Control(String),
    Policy(String),
    Gaps,
    Stale(u32),
    Active,
    Matrix,
    Lint,
}

pub fn run(mode: Mode, json_out: bool) -> Result<()> {
    // Generate provenance manifest
    let manifest = provenance::generate_manifest(None)?;

    match mode {
        Mode::Report => report(&manifest, json_out),
        Mode::Trace(way) => trace(&manifest, &way, json_out),
        Mode::Control(pattern) => control(&manifest, &pattern, json_out),
        Mode::Policy(pattern) => policy(&manifest, &pattern, json_out),
        Mode::Gaps => gaps(&manifest, json_out),
        Mode::Stale(days) => stale(&manifest, days, json_out),
        Mode::Active => active(&manifest, json_out),
        Mode::Matrix => matrix(&manifest, json_out),
        Mode::Lint => lint(&manifest, json_out),
    }
}

// ── Report ─────────────────────────────────────────────────────

fn report(manifest: &Value, json_out: bool) -> Result<()> {
    let total = manifest["ways_scanned"].as_u64().unwrap_or(0);
    let with = manifest["ways_with_provenance"].as_u64().unwrap_or(0);
    let without = manifest["ways_without_provenance"].as_u64().unwrap_or(0);
    let policies = obj_len(&manifest["coverage"]["by_policy"]);
    let controls = obj_len(&manifest["coverage"]["by_control"]);

    let stale_ways = find_stale_ways(manifest, 90);
    let incomplete = find_incomplete(manifest);

    if json_out {
        let result = json!({
            "total_ways": total,
            "with_provenance": with,
            "without_provenance": without,
            "coverage_pct": if total > 0 { with * 100 / total } else { 0 },
            "policy_sources": policies,
            "control_references": controls,
            "stale_ways": stale_ways,
            "incomplete_ways": incomplete,
        });
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    println!();
    println!("\x1b[1mProvenance Coverage Report\x1b[0m");
    println!();

    if total > 0 {
        let pct = with * 100 / total;
        let color = if pct >= 75 {
            "\x1b[0;32m"
        } else if pct >= 40 {
            "\x1b[1;33m"
        } else {
            "\x1b[0;31m"
        };
        println!("  Ways scanned:        {:3}", total);
        println!(
            "  With provenance:     {}{:3} ({}%)\x1b[0m",
            color, with, pct
        );
        println!("  Without provenance:  {:3}", without);
    } else {
        println!("  Ways scanned:        {:3}", total);
    }
    println!();

    // Policy sources
    println!(
        "\x1b[1mPolicy Sources\x1b[0m \x1b[2m({policies}):\x1b[0m"
    );
    if let Some(by_policy) = manifest["coverage"]["by_policy"].as_object() {
        for (uri, ways) in by_policy {
            println!("  \x1b[0;36m{uri}\x1b[0m");
            if let Some(arr) = ways.as_array() {
                let names: Vec<&str> = arr.iter().filter_map(|v| v.as_str()).collect();
                println!("    \x1b[2m→ {}\x1b[0m", names.join(", "));
            }
        }
    }
    println!();

    // Control references
    println!(
        "\x1b[1mControl References\x1b[0m \x1b[2m({controls}):\x1b[0m"
    );
    if let Some(by_control) = manifest["coverage"]["by_control"].as_object() {
        for (cid, ways) in by_control {
            println!("  {cid}");
            if let Some(arr) = ways.as_array() {
                let names: Vec<&str> = arr.iter().filter_map(|v| v.as_str()).collect();
                println!("    \x1b[2m→ {}\x1b[0m", names.join(", "));
            }
        }
    }
    println!();

    if !stale_ways.is_empty() {
        println!(
            "\x1b[1mStale Provenance\x1b[0m \x1b[1;33m(verified > 90 days ago):\x1b[0m"
        );
        for way in &stale_ways {
            if let Some(verified) = manifest["ways"][way]["provenance"]["verified"].as_str() {
                println!("  \x1b[1;33m{way}\x1b[0m \x1b[2m(verified: {verified})\x1b[0m");
            }
        }
        println!();
    }

    if !incomplete.is_empty() {
        println!(
            "\x1b[1mIncomplete Provenance\x1b[0m \x1b[1;33m(missing policy, controls, or rationale):\x1b[0m"
        );
        for way in &incomplete {
            println!("  \x1b[1;33m{way}\x1b[0m");
        }
        println!();
    }

    // Ways without provenance
    println!("\x1b[1mWays without provenance:\x1b[0m");
    if let Some(arr) = manifest["coverage"]["without_provenance"].as_array() {
        for way in arr {
            if let Some(s) = way.as_str() {
                println!("  \x1b[2m{s}\x1b[0m");
            }
        }
    }
    println!();

    Ok(())
}

// ── Trace ──────────────────────────────────────────────────────

fn trace(manifest: &Value, way_id: &str, json_out: bool) -> Result<()> {
    let way_data = &manifest["ways"][way_id];
    if way_data.is_null() {
        let available: Vec<&str> = manifest["ways"]
            .as_object()
            .map(|m| m.keys().map(|k| k.as_str()).collect())
            .unwrap_or_default();
        bail!(
            "way '{}' not found in manifest. Available:\n  {}",
            way_id,
            available.join("\n  ")
        );
    }

    if json_out {
        let mut out = way_data.clone();
        if let Some(obj) = out.as_object_mut() {
            obj.insert("way".to_string(), json!(way_id));
        }
        println!("{}", serde_json::to_string_pretty(&out)?);
        return Ok(());
    }

    println!();
    println!(
        "\x1b[1mProvenance Trace: \x1b[0;36m{way_id}\x1b[0m"
    );
    println!();
    if let Some(path) = way_data["path"].as_str() {
        println!("  File: \x1b[2m{path}\x1b[0m");
    }
    println!();

    let prov = &way_data["provenance"];
    if prov.is_null() {
        println!("  \x1b[1;33m(no provenance metadata)\x1b[0m");
        return Ok(());
    }

    // Policies
    println!("\x1b[1mPolicy sources:\x1b[0m");
    if let Some(policies) = prov["policy"].as_array() {
        for p in policies {
            let ptype = p["type"].as_str().unwrap_or("unknown");
            let uri = p["uri"].as_str().unwrap_or("");
            println!("  {ptype}: {uri}");
        }
    }
    println!();

    // Controls
    println!("\x1b[1mControls:\x1b[0m");
    if let Some(controls) = prov["controls"].as_array() {
        for c in controls {
            if let Some(obj) = c.as_object() {
                let cid = obj.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                println!("  {cid}");
                if let Some(justifications) = obj.get("justifications").and_then(|v| v.as_array()) {
                    for j in justifications {
                        if let Some(s) = j.as_str() {
                            println!("    ✓ {s}");
                        }
                    }
                }
            } else if let Some(s) = c.as_str() {
                println!("  {s}");
            }
        }
    }
    println!();

    // Verified
    match prov["verified"].as_str() {
        Some(v) => println!("  Verified: \x1b[0;32m{v}\x1b[0m"),
        None => println!("  Verified: \x1b[1;33mnot set\x1b[0m"),
    }
    println!();

    // Rationale
    if let Some(rationale) = prov["rationale"].as_str() {
        println!("\x1b[1mRationale:\x1b[0m");
        println!("  {rationale}");
    }

    // Firing history from stats
    print_firing_history(way_id);

    Ok(())
}

// ── Control ────────────────────────────────────────────────────

fn control(manifest: &Value, pattern: &str, json_out: bool) -> Result<()> {
    let by_control = match manifest["coverage"]["by_control"].as_object() {
        Some(m) => m,
        None => bail!("No control data in manifest"),
    };

    let pattern_lower = pattern.to_lowercase();
    let matches: Vec<(&String, &Value)> = by_control
        .iter()
        .filter(|(k, _)| k.to_lowercase().contains(&pattern_lower))
        .collect();

    if matches.is_empty() {
        let available: Vec<&String> = by_control.keys().collect();
        bail!(
            "No controls matching '{}'. Available:\n  {}",
            pattern,
            available.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("\n  ")
        );
    }

    if json_out {
        let result: Vec<Value> = matches
            .iter()
            .map(|(k, v)| json!({"control": k, "data": v}))
            .collect();
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    println!(
        "\x1b[1mControls matching\x1b[0m '\x1b[0;36m{pattern}\x1b[0m':"
    );
    println!();
    for (cid, ways) in &matches {
        println!("  {cid}");
        if let Some(arr) = ways.as_array() {
            let names: Vec<&str> = arr.iter().filter_map(|v| v.as_str()).collect();
            println!("    implementing: {}", names.join(", "));
        }
        println!();
    }

    Ok(())
}

// ── Policy ─────────────────────────────────────────────────────

fn policy(manifest: &Value, pattern: &str, json_out: bool) -> Result<()> {
    let by_policy = match manifest["coverage"]["by_policy"].as_object() {
        Some(m) => m,
        None => bail!("No policy data in manifest"),
    };

    let pattern_lower = pattern.to_lowercase();
    let matches: Vec<(&String, &Value)> = by_policy
        .iter()
        .filter(|(k, _)| k.to_lowercase().contains(&pattern_lower))
        .collect();

    if matches.is_empty() {
        let available: Vec<&String> = by_policy.keys().collect();
        bail!(
            "No policies matching '{}'. Available:\n  {}",
            pattern,
            available.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("\n  ")
        );
    }

    if json_out {
        let result: Vec<Value> = matches
            .iter()
            .map(|(k, v)| json!({"policy": k, "data": v}))
            .collect();
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    println!(
        "\x1b[1mPolicies matching\x1b[0m '\x1b[0;36m{pattern}\x1b[0m':"
    );
    println!();
    for (uri, ways) in &matches {
        println!("  {uri}");
        if let Some(arr) = ways.as_array() {
            let names: Vec<&str> = arr.iter().filter_map(|v| v.as_str()).collect();
            println!("    implementing ways: {}", names.join(", "));
        }
        println!();
    }

    Ok(())
}

// ── Gaps ───────────────────────────────────────────────────────

fn gaps(manifest: &Value, json_out: bool) -> Result<()> {
    let without = &manifest["coverage"]["without_provenance"];

    if json_out {
        println!("{}", serde_json::to_string_pretty(without)?);
        return Ok(());
    }

    let total = manifest["ways_scanned"].as_u64().unwrap_or(0);
    let count = manifest["ways_without_provenance"].as_u64().unwrap_or(0);

    println!();
    println!(
        "\x1b[1mWays Without Provenance\x1b[0m \x1b[1;33m({count} of {total})\x1b[0m"
    );
    println!();
    if let Some(arr) = without.as_array() {
        for way in arr {
            if let Some(s) = way.as_str() {
                println!("  {s}");
            }
        }
    }

    Ok(())
}

// ── Stale ──────────────────────────────────────────────────────

fn stale(manifest: &Value, days: u32, json_out: bool) -> Result<()> {
    let stale_ways = find_stale_ways(manifest, days);

    if json_out {
        let result: Vec<Value> = stale_ways
            .iter()
            .filter_map(|way| {
                let verified = manifest["ways"][way.as_str()]["provenance"]["verified"]
                    .as_str()?
                    .to_string();
                Some(json!({"way": way, "verified": verified}))
            })
            .collect();
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    let cutoff = cutoff_date(days);
    println!();
    println!(
        "\x1b[1mStale Provenance\x1b[0m \x1b[2m(verified > {days} days ago, cutoff: {cutoff})\x1b[0m"
    );
    println!();

    if stale_ways.is_empty() {
        println!("  \x1b[0;32mAll provenance dates are current.\x1b[0m");
    } else {
        for way in &stale_ways {
            let verified = manifest["ways"][way.as_str()]["provenance"]["verified"]
                .as_str()
                .unwrap_or("?");
            println!("  {way}  (verified: {verified})");
        }
    }

    Ok(())
}

// ── Active ─────────────────────────────────────────────────────

fn active(manifest: &Value, json_out: bool) -> Result<()> {
    let stats = load_events();
    let fire_counts = count_fires(&stats);

    let with_prov = match manifest["coverage"]["with_provenance"].as_array() {
        Some(a) => a,
        None => {
            println!("No provenance data.");
            return Ok(());
        }
    };

    if json_out {
        let result: Vec<Value> = with_prov
            .iter()
            .filter_map(|v| {
                let way = v.as_str()?;
                let fires = fire_counts.get(way).copied().unwrap_or(0);
                Some(json!({"way": way, "fires": fires}))
            })
            .collect();
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    let total_governed = manifest["ways_with_provenance"].as_u64().unwrap_or(0);
    let total_ways = manifest["ways_scanned"].as_u64().unwrap_or(0);

    println!();
    println!("\x1b[1mActive Governance Report\x1b[0m");
    println!();
    println!(
        "  Governed ways: \x1b[0;32m{total_governed}\x1b[0m of {total_ways}"
    );
    println!();
    println!(
        "  \x1b[1m{:<28} {:>5}  {}\x1b[0m",
        "Way", "Fires", "Status"
    );
    println!(
        "  \x1b[2m{:<28} {:>5}  {}\x1b[0m",
        "---", "-----", "------"
    );

    for v in with_prov {
        let way = match v.as_str() {
            Some(s) => s,
            None => continue,
        };
        let fires = fire_counts.get(way).copied().unwrap_or(0);
        let status = if fires > 0 {
            "\x1b[0;32mactive\x1b[0m"
        } else {
            "\x1b[2mdormant\x1b[0m"
        };
        println!("  {:<28} {:>5}  {}", way, fires, status);
    }

    // Ungoverned with high fire counts
    println!();
    println!(
        "\x1b[1mUngoverned ways\x1b[0m \x1b[2m(top by fire count):\x1b[0m"
    );
    if let Some(without) = manifest["coverage"]["without_provenance"].as_array() {
        let mut ungov_fires: Vec<(&str, u64)> = without
            .iter()
            .filter_map(|v| {
                let way = v.as_str()?;
                let fires = fire_counts.get(way).copied().unwrap_or(0);
                if fires > 0 {
                    Some((way, fires))
                } else {
                    None
                }
            })
            .collect();
        ungov_fires.sort_by(|a, b| b.1.cmp(&a.1));

        if ungov_fires.is_empty() {
            println!("  (no firing data for ungoverned ways)");
        } else {
            for (way, fires) in ungov_fires.iter().take(5) {
                println!(
                    "  {:<28} {:>5} fires \x1b[1;33m(no provenance)\x1b[0m",
                    way, fires
                );
            }
        }
    }

    Ok(())
}

// ── Matrix ─────────────────────────────────────────────────────

fn matrix(manifest: &Value, json_out: bool) -> Result<()> {
    let ways = match manifest["ways"].as_object() {
        Some(m) => m,
        None => {
            println!("No ways data.");
            return Ok(());
        }
    };

    // Collect rows: (way, control, justification)
    let mut rows: Vec<(String, String, String)> = Vec::new();

    for (way_id, data) in ways {
        let prov = &data["provenance"];
        if prov.is_null() {
            continue;
        }
        if let Some(controls) = prov["controls"].as_array() {
            for c in controls {
                if let Some(obj) = c.as_object() {
                    let cid = obj
                        .get("id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("?")
                        .to_string();
                    if let Some(justifications) =
                        obj.get("justifications").and_then(|v| v.as_array())
                    {
                        if justifications.is_empty() {
                            rows.push((way_id.clone(), cid, "(no justification)".to_string()));
                        } else {
                            for j in justifications {
                                rows.push((
                                    way_id.clone(),
                                    cid.clone(),
                                    j.as_str().unwrap_or("").to_string(),
                                ));
                            }
                        }
                    } else {
                        rows.push((way_id.clone(), cid, "(no justification)".to_string()));
                    }
                } else if let Some(s) = c.as_str() {
                    rows.push((
                        way_id.clone(),
                        s.to_string(),
                        "(legacy — no justification)".to_string(),
                    ));
                }
            }
        }
    }

    rows.sort();

    if json_out {
        let result: Vec<Value> = rows
            .iter()
            .map(|(w, c, j)| json!({"way": w, "control": c, "justification": j}))
            .collect();
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    println!();
    println!("\x1b[1mGovernance Traceability Matrix\x1b[0m");
    println!();
    println!(
        "  \x1b[1m{:<28} {:<50} {}\x1b[0m",
        "WAY", "CONTROL", "JUSTIFICATION"
    );
    println!(
        "  \x1b[2m{:<28} {:<50} {}\x1b[0m",
        "---", "-------", "-------------"
    );

    for (way, ctrl, just) in &rows {
        println!("  {:<28} {:<50} {}", way, &ctrl[..ctrl.len().min(50)], just);
    }

    let total_c = rows.len();
    let total_j = rows.iter().filter(|(_, _, j)| !j.starts_with('(')).count();
    println!();
    println!(
        "  \x1b[2mTotal: {total_c} control claims, {total_j} justifications\x1b[0m"
    );

    Ok(())
}

// ── Lint ───────────────────────────────────────────────────────

fn lint(manifest: &Value, json_out: bool) -> Result<()> {
    let ways = match manifest["ways"].as_object() {
        Some(m) => m,
        None => {
            println!("No ways data.");
            return Ok(());
        }
    };

    let mut errors: Vec<(String, String)> = Vec::new();
    let mut warnings: Vec<(String, String)> = Vec::new();

    for (way_id, data) in ways {
        let prov = &data["provenance"];
        if prov.is_null() {
            continue;
        }

        // Check: controls exist
        let ctrl_count = prov["controls"]
            .as_array()
            .map(|a| a.len())
            .unwrap_or(0);
        if ctrl_count == 0 {
            errors.push((
                way_id.clone(),
                "provenance declared but no controls listed".to_string(),
            ));
        }

        // Check: structured controls have justifications
        if let Some(controls) = prov["controls"].as_array() {
            for c in controls {
                if let Some(obj) = c.as_object() {
                    let cid = obj.get("id").and_then(|v| v.as_str()).unwrap_or("?");
                    let j_count = obj
                        .get("justifications")
                        .and_then(|v| v.as_array())
                        .map(|a| a.len())
                        .unwrap_or(0);
                    if j_count == 0 {
                        warnings.push((
                            way_id.clone(),
                            format!("control has no justifications: {cid}"),
                        ));
                    }
                }
            }

            // Check: legacy string controls
            let legacy_count = controls.iter().filter(|c| c.is_string()).count();
            if legacy_count > 0 {
                warnings.push((
                    way_id.clone(),
                    format!("{legacy_count} control(s) in legacy format (no justifications)"),
                ));
            }
        }

        // Check: policy URIs reference real files
        if let Some(policies) = prov["policy"].as_array() {
            for p in policies {
                if let Some(uri) = p["uri"].as_str() {
                    if !uri.starts_with("github://") && !uri.starts_with("http") {
                        let home = std::env::var("HOME").unwrap_or_default();
                        let full = format!("{home}/.claude/{uri}");
                        if !std::path::Path::new(&full).exists() {
                            errors.push((
                                way_id.clone(),
                                format!("policy URI not found: {uri}"),
                            ));
                        }
                    }
                }
            }
        }

        // Check: verified date
        match prov["verified"].as_str() {
            None => {
                warnings.push((way_id.clone(), "no verified date".to_string()));
            }
            Some(v) => {
                let re = regex::Regex::new(r"^\d{4}-\d{2}-\d{2}$").unwrap();
                if !re.is_match(v) {
                    errors.push((
                        way_id.clone(),
                        format!("invalid verified date: {v}"),
                    ));
                }
            }
        }

        // Check: rationale
        if prov["rationale"].as_str().is_none() {
            warnings.push((way_id.clone(), "no rationale".to_string()));
        }
    }

    errors.sort();
    warnings.sort();

    let error_count = errors.len();
    let warning_count = warnings.len();

    if json_out {
        let result = json!({
            "errors": error_count,
            "warnings": warning_count,
            "passed": error_count == 0,
            "error_details": errors.iter().map(|(w, m)| json!({"way": w, "message": m})).collect::<Vec<_>>(),
            "warning_details": warnings.iter().map(|(w, m)| json!({"way": w, "message": m})).collect::<Vec<_>>(),
        });
        println!("{}", serde_json::to_string_pretty(&result)?);
        if error_count > 0 {
            std::process::exit(1);
        }
        return Ok(());
    }

    println!();
    println!("\x1b[1mGovernance Lint Report\x1b[0m");
    println!();

    for (way, msg) in &errors {
        println!(
            "  \x1b[0;31m{:<6}\x1b[0m [{:<28}] {}",
            "ERROR", way, msg
        );
    }
    for (way, msg) in &warnings {
        println!(
            "  \x1b[1;33m{:<6}\x1b[0m [{:<28}] {}",
            "WARN", way, msg
        );
    }

    if error_count == 0 && warning_count == 0 {
        println!("  \x1b[0;32mAll provenance checks passed.\x1b[0m");
    } else {
        println!();
        println!(
            "  Results: \x1b[0;31m{error_count} error(s)\x1b[0m, \x1b[1;33m{warning_count} warning(s)\x1b[0m"
        );
        if error_count > 0 {
            println!("  \x1b[0;31mLint FAILED — errors must be resolved.\x1b[0m");
            std::process::exit(1);
        }
    }

    Ok(())
}

// ── Helpers ────────────────────────────────────────────────────

fn obj_len(v: &Value) -> usize {
    v.as_object().map(|m| m.len()).unwrap_or(0)
}

fn cutoff_date(days: u32) -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let cutoff_secs = secs.saturating_sub(days as u64 * 86400);
    let days_since = cutoff_secs / 86400;
    let (y, m, d) = crate::session::days_to_ymd_pub(days_since);
    format!("{y:04}-{m:02}-{d:02}")
}

fn find_stale_ways(manifest: &Value, days: u32) -> Vec<String> {
    let cutoff = cutoff_date(days);
    let mut stale = Vec::new();

    if let Some(ways) = manifest["ways"].as_object() {
        for (way_id, data) in ways {
            if let Some(verified) = data["provenance"]["verified"].as_str() {
                if verified < cutoff.as_str() {
                    stale.push(way_id.clone());
                }
            }
        }
    }
    stale.sort();
    stale
}

fn find_incomplete(manifest: &Value) -> Vec<String> {
    let mut incomplete = Vec::new();

    if let Some(ways) = manifest["ways"].as_object() {
        for (way_id, data) in ways {
            let prov = &data["provenance"];
            if prov.is_null() {
                continue;
            }
            let missing_policy = prov["policy"]
                .as_array()
                .map(|a| a.is_empty())
                .unwrap_or(true);
            let missing_controls = prov["controls"]
                .as_array()
                .map(|a| a.is_empty())
                .unwrap_or(true);
            let missing_rationale = prov["rationale"].as_str().is_none();

            if missing_policy || missing_controls || missing_rationale {
                incomplete.push(way_id.clone());
            }
        }
    }
    incomplete.sort();
    incomplete
}

fn load_events() -> Vec<Value> {
    let home = std::env::var("HOME").unwrap_or_default();
    let path = format!("{home}/.claude/stats/events.jsonl");
    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    content
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

fn count_fires(events: &[Value]) -> HashMap<String, u64> {
    let mut counts: HashMap<String, u64> = HashMap::new();
    for event in events {
        if event["event"].as_str() == Some("way_fired") {
            if let Some(way) = event["way"].as_str() {
                *counts.entry(way.to_string()).or_default() += 1;
            }
        }
    }
    counts
}

fn print_firing_history(way_id: &str) {
    let events = load_events();
    let fires: Vec<&str> = events
        .iter()
        .filter(|e| {
            e["event"].as_str() == Some("way_fired") && e["way"].as_str() == Some(way_id)
        })
        .filter_map(|e| e["ts"].as_str())
        .collect();

    if !fires.is_empty() {
        let first = fires.first().map(|s| &s[..10.min(s.len())]).unwrap_or("?");
        let last = fires.last().map(|s| &s[..10.min(s.len())]).unwrap_or("?");
        println!();
        println!("Firing history: {} times ({first} → {last})", fires.len());
    }
}
