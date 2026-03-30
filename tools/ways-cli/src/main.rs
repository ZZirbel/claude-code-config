use anyhow::Result;
use clap::{Parser, Subcommand};

mod bm25;
mod cmd;
mod frontmatter;
mod scanner;
pub mod session;

#[derive(Parser)]
#[command(name = "ways", version, about = "Unified CLI for ways knowledge guidance")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Validate way frontmatter against the schema
    Lint {
        /// Path to scan (default: global ways directory)
        path: Option<String>,
        /// Show the frontmatter schema reference
        #[arg(long)]
        schema: bool,
        /// Exit non-zero on errors (for CI)
        #[arg(long)]
        check: bool,
    },
    /// Generate the ways corpus for matching engines
    Corpus {
        /// Ways root directory (default: ~/.claude/hooks/ways)
        #[arg(long)]
        ways_dir: Option<String>,
        /// Suppress progress output
        #[arg(long, short)]
        quiet: bool,
        /// Only regenerate if corpus is stale (newer way files exist)
        #[arg(long)]
        if_stale: bool,
    },
    /// Score a query against ways using BM25
    Match {
        /// The query string to match
        query: String,
        /// Path to corpus JSONL
        #[arg(long)]
        corpus: Option<String>,
    },
    /// Score a query against ways using embedding similarity
    Embed {
        /// The query string to match
        query: String,
        /// Path to corpus JSONL
        #[arg(long)]
        corpus: Option<String>,
        /// Path to GGUF model file
        #[arg(long)]
        model: Option<String>,
    },
    /// Score way-vs-way cosine similarity
    Siblings {
        /// Way ID to compare (or "all" for full matrix)
        id: String,
        /// Minimum similarity threshold to display
        #[arg(long, default_value = "0.3")]
        threshold: f64,
        /// Path to corpus JSONL
        #[arg(long)]
        corpus: Option<String>,
        /// Path to GGUF model file
        #[arg(long)]
        model: Option<String>,
    },
    /// Export ways as a JSONL graph (nodes + edges)
    Graph {
        /// Ways root directory (default: ~/.claude/hooks/ways)
        #[arg(long)]
        ways_dir: Option<String>,
        /// Output file (default: stdout)
        #[arg(long, short)]
        output: Option<String>,
    },
    /// Analyze progressive disclosure tree structure
    Tree {
        /// Way path or short name (e.g., "supplychain" or full path)
        path: String,
        /// Show Jaccard similarity between siblings
        #[arg(long)]
        jaccard: bool,
    },
    /// Scan provenance sidecars
    Provenance {
        /// Ways root directory (default: ~/.claude/hooks/ways)
        #[arg(long)]
        ways_dir: Option<String>,
    },
    /// Display a way, check, or core guidance (session-aware)
    Show {
        #[command(subcommand)]
        what: ShowCommand,
    },
    /// Analyze a way file and suggest vocabulary improvements
    Suggest {
        /// Path to a way file
        file: String,
        /// Minimum term frequency for suggestions
        #[arg(long, default_value = "2")]
        min_freq: u32,
    },
    /// Usage statistics from event log
    Stats {
        /// Last N days only
        #[arg(long)]
        days: Option<u32>,
        /// Filter to specific project path
        #[arg(long)]
        project: Option<String>,
        /// Machine-readable JSON output
        #[arg(long)]
        json: bool,
    },
    /// List ways triggered in the current session
    List {
        /// Session ID (if omitted, shows all recent markers)
        #[arg(long)]
        session: Option<String>,
    },
    /// Engine health dashboard — binary, model, corpus, project status
    Status {
        /// Machine-readable JSON output
        #[arg(long)]
        json: bool,
    },
    /// Scan ways and output matched content (replaces hook scan loops)
    Scan {
        #[command(subcommand)]
        mode: ScanCommand,
    },
}

#[derive(Subcommand)]
enum ScanCommand {
    /// Scan ways against a user prompt (keyword + semantic matching)
    Prompt {
        /// User prompt text (lowercase)
        #[arg(long)]
        query: String,
        /// Session ID
        #[arg(long)]
        session: String,
        /// Project directory
        #[arg(long)]
        project: Option<String>,
    },
    /// Scan ways against a bash command
    Command {
        /// Command string
        #[arg(long)]
        command: String,
        /// Tool description
        #[arg(long)]
        description: Option<String>,
        /// Session ID
        #[arg(long)]
        session: String,
        /// Project directory
        #[arg(long)]
        project: Option<String>,
    },
    /// Scan ways against a file path
    File {
        /// File path being edited
        #[arg(long)]
        path: String,
        /// Session ID
        #[arg(long)]
        session: String,
        /// Project directory
        #[arg(long)]
        project: Option<String>,
    },
    /// Evaluate state-based triggers (context-threshold, file-exists, session-start)
    State {
        /// Session ID
        #[arg(long)]
        session: String,
        /// Project directory
        #[arg(long)]
        project: Option<String>,
        /// Transcript path (for context-threshold)
        #[arg(long)]
        transcript: Option<String>,
    },
}

#[derive(Subcommand)]
enum ShowCommand {
    /// Display a way (session-aware, idempotent)
    Way {
        /// Way ID (e.g., "softwaredev/code/quality")
        id: String,
        /// Session ID
        #[arg(long)]
        session: String,
        /// Trigger channel (keyword, semantic:embedding, semantic:bm25)
        #[arg(long, default_value = "unknown")]
        trigger: String,
    },
    /// Display a check (with scoring curve)
    Check {
        /// Way ID containing the check
        id: String,
        /// Session ID
        #[arg(long)]
        session: String,
        /// Trigger channel
        #[arg(long, default_value = "unknown")]
        trigger: String,
        /// Match score from the matching engine
        #[arg(long, default_value = "0")]
        score: f64,
    },
    /// Display core guidance (session start)
    Core {
        /// Session ID
        #[arg(long)]
        session: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Lint { path, schema, check } => cmd::lint::run(path, schema, check),
        Commands::Corpus { ways_dir, quiet, if_stale } => cmd::corpus::run(ways_dir, quiet, if_stale),
        Commands::Match { query, corpus } => cmd::match_bm25::run(query, corpus),
        Commands::Embed { query, corpus, model } => cmd::embed::run(query, corpus, model),
        Commands::Siblings { id, threshold, corpus, model } => {
            cmd::siblings::run(id, threshold, corpus, model)
        }
        Commands::Graph { ways_dir, output } => cmd::graph::run(ways_dir, output),
        Commands::Tree { path, jaccard } => cmd::tree::run(path, jaccard),
        Commands::Provenance { ways_dir } => cmd::provenance::run(ways_dir),
        Commands::Stats { days, project, json } => {
            cmd::stats::run(days, project.as_deref(), json)
        }
        Commands::List { session } => cmd::list::run(session.as_deref()),
        Commands::Status { json } => cmd::status::run(json),
        Commands::Scan { mode } => match mode {
            ScanCommand::Prompt { query, session, project } => {
                cmd::scan::prompt(&query, &session, project.as_deref())
            }
            ScanCommand::Command { command, description, session, project } => {
                cmd::scan::command(&command, description.as_deref(), &session, project.as_deref())
            }
            ScanCommand::File { path, session, project } => {
                cmd::scan::file(&path, &session, project.as_deref())
            }
            ScanCommand::State { session, project, transcript } => {
                cmd::scan::state(&session, project.as_deref(), transcript.as_deref())
            }
        },
        Commands::Show { what } => match what {
            ShowCommand::Way { id, session, trigger } => {
                cmd::show::way(&id, &session, &trigger)
            }
            ShowCommand::Check { id, session, trigger, score } => {
                cmd::show::check(&id, &session, &trigger, score)
            }
            ShowCommand::Core { session } => cmd::show::core(&session),
        },
        Commands::Suggest { file, min_freq } => cmd::suggest::run(file, min_freq),
    }
}
