//! Governance operator — query provenance traceability for ways.
//!
//! Replaces: governance/governance.sh (543 lines)
//! Wraps the provenance manifest with auditor-friendly query modes:
//! report, trace, control, policy, gaps, stale, active, matrix, lint.

mod audit;
mod helpers;
mod lint;
mod matrix;
mod query;
mod report;
mod trace;

use anyhow::Result;

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

pub fn run(mode: Mode, json_out: bool, global: bool) -> Result<()> {
    // Determine ways directory: project-local first, then global
    let ways_dir = if !global {
        helpers::detect_project_ways()
    } else {
        None
    };

    let manifest = provenance::generate_manifest(ways_dir)?;

    match mode {
        Mode::Report => report::run(&manifest, json_out),
        Mode::Trace(way) => trace::run(&manifest, &way, json_out),
        Mode::Control(pattern) => query::control(&manifest, &pattern, json_out),
        Mode::Policy(pattern) => query::policy(&manifest, &pattern, json_out),
        Mode::Gaps => audit::gaps(&manifest, json_out),
        Mode::Stale(days) => audit::stale(&manifest, days, json_out),
        Mode::Active => audit::active(&manifest, json_out),
        Mode::Matrix => matrix::run(&manifest, json_out),
        Mode::Lint => lint::run(&manifest, json_out),
    }
}
