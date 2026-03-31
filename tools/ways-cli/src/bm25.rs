//! BM25 scoring engine — pure Rust port of way-match.c
//!
//! Tokenizes text (lowercase, stopword removal, Porter2 stemming),
//! builds term frequency maps, and scores queries using Okapi BM25.

use rust_stemmers::{Algorithm, Stemmer};
use std::collections::HashMap;

const BM25_K1: f64 = 1.2;
const BM25_B: f64 = 0.75;

pub static STOPWORDS: &[&str] = &[
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "must", "shall", "can", "this", "that",
    "these", "those", "it", "its", "what", "how", "why", "when", "where",
    "who", "let", "lets", "just", "to", "for", "of", "in", "on", "at",
    "by", "and", "or", "but", "not", "with", "from", "into", "about",
    "than", "then", "so", "if", "up", "out", "no", "yes", "all", "some",
    "any", "each", "my", "your", "our", "me", "we", "you", "i",
];

fn is_stopword(word: &str) -> bool {
    STOPWORDS.contains(&word)
}

/// Tokenize text: split on non-alpha, lowercase, remove stopwords, Porter2 stem.
pub fn tokenize(text: &str, stemmer: &Stemmer) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();

    for ch in text.chars() {
        if ch.is_alphabetic() {
            current.extend(ch.to_lowercase());
        } else if !current.is_empty() {
            if current.len() >= 3 && !is_stopword(&current) {
                let stemmed = stemmer.stem(&current).to_string();
                if stemmed.len() >= 3 {
                    tokens.push(stemmed);
                }
            }
            current.clear();
        }
    }
    // Flush last token
    if current.len() >= 3 && !is_stopword(&current) {
        let stemmed = stemmer.stem(&current).to_string();
        if stemmed.len() >= 3 {
            tokens.push(stemmed);
        }
    }
    tokens
}

/// Term frequency map for a document.
pub struct TermFreq {
    pub counts: HashMap<String, u32>,
    pub total_tokens: u32,
}

impl TermFreq {
    pub fn from_tokens(tokens: &[String]) -> Self {
        let mut counts = HashMap::new();
        for t in tokens {
            *counts.entry(t.clone()).or_insert(0) += 1;
        }
        Self {
            total_tokens: tokens.len() as u32,
            counts,
        }
    }

    pub fn get(&self, term: &str) -> u32 {
        self.counts.get(term).copied().unwrap_or(0)
    }
}

/// A document in the corpus.
pub struct Document {
    pub id: String,
    pub description: String,
    #[allow(dead_code)] // stored for debug/diagnostics, not actively read
    pub vocabulary: String,
    pub threshold: f64,
    pub tf: TermFreq,
}

/// A corpus of documents with pre-computed term frequencies.
pub struct Corpus {
    pub docs: Vec<Document>,
    pub avg_dl: f64,
}

impl Corpus {
    pub fn new() -> Self {
        Self {
            docs: Vec::new(),
            avg_dl: 0.0,
        }
    }

    pub fn add_document(&mut self, id: String, description: String, vocabulary: String, threshold: f64, stemmer: &Stemmer) {
        let combined = format!("{description} {vocabulary}");
        let tokens = tokenize(&combined, stemmer);
        let tf = TermFreq::from_tokens(&tokens);
        self.docs.push(Document { id, description, vocabulary, threshold, tf });
    }

    pub fn compute_avg_dl(&mut self) {
        if self.docs.is_empty() {
            self.avg_dl = 0.0;
            return;
        }
        let total: u32 = self.docs.iter().map(|d| d.tf.total_tokens).sum();
        self.avg_dl = total as f64 / self.docs.len() as f64;
    }

    /// Count documents containing a term.
    fn doc_freq(&self, term: &str) -> u32 {
        self.docs.iter().filter(|d| d.tf.get(term) > 0).count() as u32
    }

    /// BM25 score of a document against query tokens.
    pub fn bm25_score(&self, doc: &Document, query_tokens: &[String]) -> f64 {
        let n = self.docs.len() as f64;
        let dl = doc.tf.total_tokens as f64;
        let avgdl = self.avg_dl;
        let mut score = 0.0;

        for term in query_tokens {
            let tf = doc.tf.get(term) as f64;
            if tf == 0.0 {
                continue;
            }

            let df = self.doc_freq(term) as f64;

            // IDF with floor of 0
            let idf = ((n - df + 0.5) / (df + 0.5) + 1.0).ln();
            let idf = if idf < 0.0 { 0.0 } else { idf };

            // BM25 TF component
            let tf_norm = (tf * (BM25_K1 + 1.0)) / (tf + BM25_K1 * (1.0 - BM25_B + BM25_B * dl / avgdl));

            score += idf * tf_norm;
        }

        score
    }
}

/// Load a JSONL corpus file into a Corpus.
pub fn load_corpus_jsonl(path: &str, stemmer: &Stemmer) -> anyhow::Result<Corpus> {
    let content = std::fs::read_to_string(path)?;
    let mut corpus = Corpus::new();

    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let entry: serde_json::Value = serde_json::from_str(line)?;
        let id = entry["id"].as_str().unwrap_or("").to_string();
        let desc = entry["description"].as_str().unwrap_or("").to_string();
        let vocab = entry["vocabulary"].as_str().unwrap_or("").to_string();
        let threshold = entry["threshold"].as_f64().unwrap_or(2.0);

        corpus.add_document(id, desc, vocab, threshold, stemmer);
    }

    corpus.compute_avg_dl();
    Ok(corpus)
}

pub fn new_stemmer() -> Stemmer {
    Stemmer::create(Algorithm::English)
}
