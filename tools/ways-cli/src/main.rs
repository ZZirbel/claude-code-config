use anyhow::Result;
use clap::{Parser, Subcommand};

mod cmd;
mod frontmatter;
mod scanner;

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
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Lint { path, schema, check } => cmd::lint::run(path, schema, check),
        Commands::Corpus { ways_dir, quiet } => cmd::corpus::run(ways_dir, quiet),
        Commands::Match { query, corpus } => cmd::match_bm25::run(query, corpus),
        Commands::Embed { query, corpus, model } => cmd::embed::run(query, corpus, model),
        Commands::Siblings { id, threshold, corpus, model } => {
            cmd::siblings::run(id, threshold, corpus, model)
        }
        Commands::Graph { ways_dir, output } => cmd::graph::run(ways_dir, output),
        Commands::Tree { path, jaccard } => cmd::tree::run(path, jaccard),
        Commands::Provenance { ways_dir } => cmd::provenance::run(ways_dir),
    }
}
