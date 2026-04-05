use anyhow::Result;
use figlet_rs::FIGlet;

/// Change this to whatever you want the banner to say.
const BANNER_TEXT: &str = "WAYS";

/// Spaced title rendered above the block text with ANSI underline.
const BANNER_TITLE: &str = "A G E N T";

/// Subtitle line printed below the banner.
const BANNER_SUBTITLE: &str = "cognitive steering for AI agents";

/// ANSI Shadow font embedded at compile time.
const ANSI_SHADOW_FLF: &str = include_str!("../../fonts/ansi-shadow.flf");

// ANSI escape helpers
const RESET: &str = "\x1b[0m";
const UNDERLINE: &str = "\x1b[4m";
const DIM: &str = "\x1b[2m";

/// 6-step gradient from warm coral to amber (256-color mode).
const GRADIENT: [&str; 7] = [
    "\x1b[38;5;209m", // coral
    "\x1b[38;5;210m", // salmon
    "\x1b[38;5;216m", // light salmon
    "\x1b[38;5;222m", // light gold
    "\x1b[38;5;179m", // gold
    "\x1b[38;5;172m", // dark gold
    "\x1b[38;5;130m", // amber
];

pub fn run() -> Result<()> {
    let font = FIGlet::from_content(ANSI_SHADOW_FLF)
        .map_err(|e| anyhow::anyhow!("font load failed: {e}"))?;
    let figure = font
        .convert(BANNER_TEXT)
        .ok_or_else(|| anyhow::anyhow!("failed to render banner text"))?;

    let rendered = figure.to_string();

    // Print spaced title with underline, aligned to block text
    println!();
    println!("  {DIM}{UNDERLINE}{BANNER_TITLE}{RESET}");
    println!();

    // Print block text with gradient color per line
    for (i, line) in rendered.lines().enumerate() {
        let color = GRADIENT[i % GRADIENT.len()];
        println!("{color}{line}{RESET}");
    }

    println!("  {DIM}{BANNER_SUBTITLE}{RESET}");
    println!();
    Ok(())
}
