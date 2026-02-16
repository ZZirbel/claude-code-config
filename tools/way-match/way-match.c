/*
 * way-match: BM25 semantic matcher for the ways system
 *
 * A lightweight text similarity tool that scores user prompts against
 * way descriptions using the Okapi BM25 ranking function.
 *
 * Two modes:
 *   pair  - score one description+vocabulary against a query (exit 0/1)
 *   score - score a JSONL corpus against a query (ranked output)
 *
 * Build: cosmocc -O2 -o way-match way-match.c
 * See: ADR-014 (docs/adr/ADR-014-tfidf-semantic-matcher.md)
 */

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Snowball Porter2 English stemmer (BSD-3-Clause, snowballstem.org) */
#include "snowball/api.h"
#include "snowball/stem_UTF_8_english.h"

#define VERSION "0.1.0"
#define MAX_TOKENS    4096
#define MAX_TOKEN_LEN 128
#define MAX_DOCS      256
#define MAX_LINE      8192

/* ========================================================================
 * Stopwords — same list as semantic-match.sh
 * ======================================================================== */

static const char *STOPWORDS[] = {
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "must", "shall", "can", "this", "that",
    "these", "those", "it", "its", "what", "how", "why", "when", "where",
    "who", "let", "lets", "just", "to", "for", "of", "in", "on", "at",
    "by", "and", "or", "but", "not", "with", "from", "into", "about",
    "than", "then", "so", "if", "up", "out", "no", "yes", "all", "some",
    "any", "each", "my", "your", "our", "me", "we", "you", "i",
    NULL
};

static int is_stopword(const char *word) {
    for (int i = 0; STOPWORDS[i]; i++) {
        if (strcmp(word, STOPWORDS[i]) == 0) return 1;
    }
    return 0;
}

/* ========================================================================
 * Tokenizer — whitespace + punctuation split, lowercase, Porter2 stem
 * ======================================================================== */

typedef struct {
    char tokens[MAX_TOKENS][MAX_TOKEN_LEN];
    int count;
} TokenList;

/* Global stemmer instance (created once, reused) */
static struct SN_env *g_stemmer = NULL;

static void stemmer_init(void) {
    if (!g_stemmer) g_stemmer = english_UTF_8_create_env();
}

static void stemmer_cleanup(void) {
    if (g_stemmer) { english_UTF_8_close_env(g_stemmer); g_stemmer = NULL; }
}

/* Stem a word in-place using Snowball Porter2 English stemmer */
static void stem_word(char *word, int *len) {
    if (!g_stemmer || *len < 3) return;

    SN_set_current(g_stemmer, *len, (const symbol *)word);
    english_UTF_8_stem(g_stemmer);

    int slen = g_stemmer->l;
    if (slen > 0 && slen < MAX_TOKEN_LEN) {
        memcpy(word, g_stemmer->p, slen);
        word[slen] = '\0';
        *len = slen;
    }
}

static void tokenize(const char *text, TokenList *out) {
    out->count = 0;
    int i = 0, len = strlen(text);

    while (i < len && out->count < MAX_TOKENS) {
        /* skip non-alpha */
        while (i < len && !isalpha((unsigned char)text[i])) i++;
        if (i >= len) break;

        /* collect alpha characters */
        char token[MAX_TOKEN_LEN];
        int t = 0;
        while (i < len && isalpha((unsigned char)text[i]) && t < MAX_TOKEN_LEN - 1) {
            token[t++] = tolower((unsigned char)text[i]);
            i++;
        }
        token[t] = '\0';

        /* skip short words and stopwords before stemming */
        if (t < 3) continue;
        if (is_stopword(token)) continue;

        /* Porter2 English stemming via Snowball */
        stem_word(token, &t);

        /* skip if stemming reduced to <3 chars */
        if (t < 3) continue;

        strcpy(out->tokens[out->count], token);
        out->count++;
    }
}

/* ========================================================================
 * Term frequency — count occurrences of each unique term
 * ======================================================================== */

typedef struct {
    char term[MAX_TOKEN_LEN];
    int count;
} TermFreq;

typedef struct {
    TermFreq entries[MAX_TOKENS];
    int count;
    int total_tokens; /* total tokens before dedup (document length) */
} TermFreqMap;

static void build_tf(const TokenList *tokens, TermFreqMap *tf) {
    tf->count = 0;
    tf->total_tokens = tokens->count;

    for (int i = 0; i < tokens->count; i++) {
        /* search existing entries */
        int found = 0;
        for (int j = 0; j < tf->count; j++) {
            if (strcmp(tf->entries[j].term, tokens->tokens[i]) == 0) {
                tf->entries[j].count++;
                found = 1;
                break;
            }
        }
        if (!found && tf->count < MAX_TOKENS) {
            strcpy(tf->entries[tf->count].term, tokens->tokens[i]);
            tf->entries[tf->count].count = 1;
            tf->count++;
        }
    }
}

static int tf_get(const TermFreqMap *tf, const char *term) {
    for (int i = 0; i < tf->count; i++) {
        if (strcmp(tf->entries[i].term, term) == 0)
            return tf->entries[i].count;
    }
    return 0;
}

/* ========================================================================
 * BM25 scorer
 *
 * BM25(q, d) = sum over query terms t:
 *   IDF(t) * (tf(t,d) * (k1 + 1)) / (tf(t,d) + k1 * (1 - b + b * |d|/avgdl))
 *
 * IDF(t) = ln((N - df(t) + 0.5) / (df(t) + 0.5) + 1)
 *   where N = number of documents, df(t) = docs containing term t
 * ======================================================================== */

typedef struct {
    char id[256];
    char description[MAX_LINE];
    char vocabulary[MAX_LINE];
    double threshold;
    TermFreqMap tf;
} Document;

typedef struct {
    Document docs[MAX_DOCS];
    int count;
    double avg_dl; /* average document length */
} Corpus;

static double bm25_k1 = 1.2;
static double bm25_b  = 0.75;

/* Count how many documents contain a given term */
static int doc_freq(const Corpus *corpus, const char *term) {
    int df = 0;
    for (int i = 0; i < corpus->count; i++) {
        if (tf_get(&corpus->docs[i].tf, term) > 0) df++;
    }
    return df;
}

/* Score a single document against a query */
static double bm25_score(const Corpus *corpus, const Document *doc,
                         const TokenList *query) {
    double score = 0.0;
    int N = corpus->count;
    double dl = doc->tf.total_tokens;
    double avgdl = corpus->avg_dl;

    for (int i = 0; i < query->count; i++) {
        const char *term = query->tokens[i];
        int tf = tf_get(&doc->tf, term);
        if (tf == 0) continue;

        int df = doc_freq(corpus, term);

        /* IDF with floor of 0 to avoid negative values for very common terms */
        double idf = log(((double)(N - df) + 0.5) / ((double)df + 0.5) + 1.0);
        if (idf < 0.0) idf = 0.0;

        /* BM25 TF component */
        double tf_norm = ((double)tf * (bm25_k1 + 1.0)) /
                         ((double)tf + bm25_k1 * (1.0 - bm25_b + bm25_b * dl / avgdl));

        score += idf * tf_norm;
    }

    return score;
}

/* ========================================================================
 * Corpus building — from arguments or JSONL file
 * ======================================================================== */

static void index_document(Document *doc) {
    /* Combine description and vocabulary into one token stream */
    char combined[MAX_LINE * 2];
    snprintf(combined, sizeof(combined), "%s %s", doc->description, doc->vocabulary);

    TokenList *tokens = calloc(1, sizeof(TokenList));
    if (!tokens) return;
    tokenize(combined, tokens);
    build_tf(tokens, &doc->tf);
    free(tokens);
}

static void compute_avg_dl(Corpus *corpus) {
    double total = 0;
    for (int i = 0; i < corpus->count; i++) {
        total += corpus->docs[i].tf.total_tokens;
    }
    corpus->avg_dl = corpus->count > 0 ? total / corpus->count : 1.0;
}

/* ========================================================================
 * JSONL corpus loading
 *
 * Minimal JSON parsing — expects one object per line with string fields:
 *   {"id":"...", "description":"...", "vocabulary":"...", "threshold":N.N}
 * ======================================================================== */

/* Extract a string value for a given key from a JSON line.
 * Matches "key" only in key position (followed by colon after optional whitespace),
 * not as a substring of a value. */
static int json_get_string(const char *json, const char *key, char *out, int maxlen) {
    char pattern[256];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    int plen = strlen(pattern);

    const char *p = json;
    while ((p = strstr(p, pattern)) != NULL) {
        const char *after = p + plen;
        /* skip whitespace, then verify colon follows (key position) */
        while (*after == ' ' || *after == '\t') after++;
        if (*after != ':') { p++; continue; }
        after++; /* skip colon */
        while (*after == ' ' || *after == '\t') after++;
        if (*after != '"') { p++; continue; }
        after++; /* skip opening quote */

        int i = 0;
        while (*after && *after != '"' && i < maxlen - 1) {
            if (*after == '\\' && *(after + 1)) {
                after++; /* skip escape */
            }
            out[i++] = *after++;
        }
        out[i] = '\0';
        return 1;
    }
    return 0;
}

static double json_get_number(const char *json, const char *key, double def) {
    char pattern[256];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    int plen = strlen(pattern);

    const char *p = json;
    while ((p = strstr(p, pattern)) != NULL) {
        const char *after = p + plen;
        while (*after == ' ' || *after == '\t') after++;
        if (*after != ':') { p++; continue; }
        after++;
        while (*after == ' ' || *after == '\t') after++;

        char buf[64];
        int i = 0;
        while (*after && (isdigit((unsigned char)*after) || *after == '.' || *after == '-') && i < 63) {
            buf[i++] = *after++;
        }
        buf[i] = '\0';
        return i > 0 ? atof(buf) : def;
    }
    return def;
}

static int load_corpus_jsonl(const char *path, Corpus *corpus) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "error: cannot open corpus file: %s\n", path);
        return -1;
    }

    char line[MAX_LINE];
    while (fgets(line, sizeof(line), f) && corpus->count < MAX_DOCS) {
        Document *doc = &corpus->docs[corpus->count];

        if (!json_get_string(line, "id", doc->id, sizeof(doc->id))) continue;
        if (!json_get_string(line, "description", doc->description, sizeof(doc->description))) continue;
        json_get_string(line, "vocabulary", doc->vocabulary, sizeof(doc->vocabulary));
        doc->threshold = json_get_number(line, "threshold", 0.4);

        index_document(doc);
        corpus->count++;
    }

    fclose(f);
    compute_avg_dl(corpus);
    return 0;
}

/* ========================================================================
 * Pair mode — single description+vocabulary vs query
 * ======================================================================== */

/* Built-in corpus for IDF computation in pair mode.
 * These are the 7 semantic ways — enough for meaningful IDF without
 * requiring a corpus file. Pair mode adds the target as an additional
 * document if it's not already one of these. */
static const struct { const char *id; const char *desc; const char *vocab; } BUILTIN_WAYS[] = {
    {"testing",     "writing unit tests, test coverage, mocking dependencies, test-driven development",
                    "unittest coverage mock tdd assertion jest pytest rspec testcase spec fixture describe expect verify"},
    {"api",         "designing REST APIs, HTTP endpoints, API versioning, request response structure",
                    "endpoint api rest route http status pagination versioning graphql request response header payload crud webhook"},
    {"debugging",   "debugging code issues, troubleshooting errors, investigating broken behavior, fixing bugs",
                    "debug breakpoint stacktrace investigate troubleshoot regression bisect crash error fail bug log trace exception segfault hang timeout"},
    {"security",    "application security, authentication, secrets management, input validation, vulnerability prevention",
                    "authentication secrets password credentials owasp injection xss sql sanitize vulnerability bcrypt hash encrypt token cert ssl tls csrf cors rotate login expose"},
    {"design",      "software system design architecture patterns database schema component modeling",
                    "architecture pattern database schema modeling interface component modules factory observer strategy monolith microservice domain layer coupling cohesion abstraction singleton"},
    {"config",      "application configuration, environment variables, dotenv files, config file management",
                    "dotenv environment configuration envvar config.json config.yaml connection port host url setting variable"},
    {"adr-context", "planning how to implement a feature, deciding an approach, understanding existing project decisions, starting work on an item, investigating why something was built a certain way",
                    "plan approach debate implement build work pick understand investigate why how decision context tradeoff evaluate option consider scope"},
    {NULL, NULL, NULL}
};

static int cmd_pair(const char *description, const char *vocabulary,
                    const char *query, double threshold) {
    Corpus *corpus = calloc(1, sizeof(Corpus));
    if (!corpus) { fprintf(stderr, "error: out of memory\n"); return 1; }

    /* Load built-in ways as corpus for IDF computation */
    for (int i = 0; BUILTIN_WAYS[i].id; i++) {
        Document *doc = &corpus->docs[corpus->count];
        snprintf(doc->id, sizeof(doc->id), "%s", BUILTIN_WAYS[i].id);
        strncpy(doc->description, BUILTIN_WAYS[i].desc, sizeof(doc->description) - 1);
        strncpy(doc->vocabulary, BUILTIN_WAYS[i].vocab, sizeof(doc->vocabulary) - 1);
        index_document(doc);
        corpus->count++;
    }

    /* Find or add the target document */
    int target_idx = -1;
    for (int i = 0; i < corpus->count; i++) {
        if (strcmp(corpus->docs[i].description, description) == 0) {
            target_idx = i;
            break;
        }
    }
    if (target_idx < 0 && corpus->count < MAX_DOCS) {
        target_idx = corpus->count;
        Document *doc = &corpus->docs[corpus->count];
        snprintf(doc->id, sizeof(doc->id), "target");
        strncpy(doc->description, description, sizeof(doc->description) - 1);
        strncpy(doc->vocabulary, vocabulary, sizeof(doc->vocabulary) - 1);
        index_document(doc);
        corpus->count++;
    }

    compute_avg_dl(corpus);

    /* Tokenize query and score with full BM25 */
    TokenList *qtokens = calloc(1, sizeof(TokenList));
    if (!qtokens) { free(corpus); return 1; }
    tokenize(query, qtokens);

    double score = bm25_score(corpus, &corpus->docs[target_idx], qtokens);

    fprintf(stderr, "match: score=%.4f threshold=%.4f\n", score, threshold);

    int result = score >= threshold ? 0 : 1;
    free(qtokens);
    free(corpus);
    return result;
}

/* ========================================================================
 * Score mode — batch scoring against JSONL corpus
 * ======================================================================== */

typedef struct {
    int index;
    double score;
} ScoredDoc;

static int cmp_scored_desc(const void *a, const void *b) {
    double sa = ((const ScoredDoc *)a)->score;
    double sb = ((const ScoredDoc *)b)->score;
    if (sb > sa) return 1;
    if (sb < sa) return -1;
    return 0;
}

static int cmd_score(const char *corpus_path, const char *query, double threshold) {
    Corpus *corpus = calloc(1, sizeof(Corpus));
    if (!corpus) { fprintf(stderr, "error: out of memory\n"); return 1; }

    if (load_corpus_jsonl(corpus_path, corpus) != 0) { free(corpus); return 1; }

    if (corpus->count == 0) {
        fprintf(stderr, "error: empty corpus\n");
        free(corpus);
        return 1;
    }

    TokenList *qtokens = calloc(1, sizeof(TokenList));
    if (!qtokens) { free(corpus); return 1; }
    tokenize(query, qtokens);

    /* Score all documents */
    ScoredDoc scored[MAX_DOCS];
    for (int i = 0; i < corpus->count; i++) {
        scored[i].index = i;
        scored[i].score = bm25_score(corpus, &corpus->docs[i], qtokens);
    }

    /* Sort descending by score */
    qsort(scored, corpus->count, sizeof(ScoredDoc), cmp_scored_desc);

    /* Output matches above threshold */
    int printed = 0;
    for (int i = 0; i < corpus->count; i++) {
        Document *doc = &corpus->docs[scored[i].index];
        double doc_thresh = doc->threshold > 0 ? doc->threshold : threshold;

        if (scored[i].score >= doc_thresh) {
            /* Truncate description for display */
            char snippet[60];
            strncpy(snippet, doc->description, 56);
            snippet[56] = '\0';
            if (strlen(doc->description) > 56) strcat(snippet, "...");

            printf("%s\t%.4f\t%s\n", doc->id, scored[i].score, snippet);
            printed++;
        }
    }

    free(qtokens);
    free(corpus);

    if (printed == 0) {
        fprintf(stderr, "no matches above threshold\n");
        return 1;
    }

    return 0;
}

/* ========================================================================
 * Suggest mode — analyze way.md body and suggest vocabulary improvements
 *
 * Reads a way.md file, tokenizes the body (stripping frontmatter),
 * compares body term frequencies against current description+vocabulary,
 * and outputs: gaps (body terms not covered), coverage, unused vocab terms,
 * and a suggested vocabulary line.
 *
 * Pure analysis — never writes files. File mutation is the shell wrapper's job.
 * ======================================================================== */

#define MAX_BODY 65536

/* Token pair: preserves original (lowercased) form alongside stem */
typedef struct {
    char stem[MAX_TOKEN_LEN];
    char original[MAX_TOKEN_LEN];
} TokenPair;

typedef struct {
    TokenPair pairs[MAX_TOKENS];
    int count;
} TokenPairList;

/* Tokenize preserving original form before stemming */
static void tokenize_pairs(const char *text, TokenPairList *out) {
    out->count = 0;
    int i = 0, len = strlen(text);

    while (i < len && out->count < MAX_TOKENS) {
        while (i < len && !isalpha((unsigned char)text[i])) i++;
        if (i >= len) break;

        char token[MAX_TOKEN_LEN];
        int t = 0;
        while (i < len && isalpha((unsigned char)text[i]) && t < MAX_TOKEN_LEN - 1) {
            token[t++] = tolower((unsigned char)text[i]);
            i++;
        }
        token[t] = '\0';

        if (t < 3 || is_stopword(token)) continue;

        /* Save lowercased original before stemming */
        strcpy(out->pairs[out->count].original, token);

        stem_word(token, &t);
        if (t < 3) continue;

        strcpy(out->pairs[out->count].stem, token);
        out->count++;
    }
}

/* Suggest entry: stem + best original + frequency + coverage flag */
typedef struct {
    char stem[MAX_TOKEN_LEN];
    char original[MAX_TOKEN_LEN];
    int freq;
    int covered; /* already in description or vocabulary */
} SuggestEntry;

static int cmp_suggest_freq(const void *a, const void *b) {
    return ((const SuggestEntry *)b)->freq - ((const SuggestEntry *)a)->freq;
}

static int cmd_suggest(const char *filepath, int min_freq) {
    /* --- 1. Read the entire file --- */
    FILE *f = fopen(filepath, "r");
    if (!f) { fprintf(stderr, "error: cannot open %s\n", filepath); return 1; }

    char *content = malloc(MAX_BODY);
    if (!content) { fclose(f); fprintf(stderr, "error: out of memory\n"); return 1; }
    int total = fread(content, 1, MAX_BODY - 1, f);
    content[total] = '\0';
    fclose(f);

    /* --- 2. Parse frontmatter and body --- */
    if (total < 4 || strncmp(content, "---\n", 4) != 0) {
        fprintf(stderr, "error: no YAML frontmatter found in %s\n", filepath);
        free(content);
        return 1;
    }

    char *fm_start = content + 4;
    char *fm_end = strstr(fm_start, "\n---\n");
    if (!fm_end) {
        fm_end = strstr(fm_start, "\n---");
        if (!fm_end) {
            fprintf(stderr, "error: unterminated frontmatter in %s\n", filepath);
            free(content);
            return 1;
        }
    }

    /* Extract description and vocabulary from frontmatter */
    char description[MAX_LINE] = "";
    char vocabulary[MAX_LINE] = "";

    char *line = fm_start;
    while (line < fm_end) {
        char *eol = strchr(line, '\n');
        if (!eol || eol > fm_end) eol = fm_end;

        if (strncmp(line, "vocabulary:", 11) == 0) {
            char *val = line + 11;
            while (*val == ' ') val++;
            int vlen = eol - val;
            if (vlen > (int)sizeof(vocabulary) - 1) vlen = sizeof(vocabulary) - 1;
            strncpy(vocabulary, val, vlen);
            vocabulary[vlen] = '\0';
        }
        if (strncmp(line, "description:", 12) == 0) {
            char *val = line + 12;
            while (*val == ' ') val++;
            int vlen = eol - val;
            if (vlen > (int)sizeof(description) - 1) vlen = sizeof(description) - 1;
            strncpy(description, val, vlen);
            description[vlen] = '\0';
        }

        line = eol + 1;
    }

    /* Body is everything after the closing --- */
    char *body_start = fm_end + 4; /* skip \n--- */
    if (body_start < content + total && *body_start == '\n') body_start++;
    if (body_start > content + total) body_start = content + total;

    /* --- 3. Tokenize body with original forms --- */
    TokenPairList *body_pairs = calloc(1, sizeof(TokenPairList));
    if (!body_pairs) { free(content); return 1; }
    tokenize_pairs(body_start, body_pairs);

    /* --- 4. Build body term frequency map --- */
    SuggestEntry *entries = calloc(MAX_TOKENS, sizeof(SuggestEntry));
    if (!entries) { free(body_pairs); free(content); return 1; }
    int entry_count = 0;

    for (int i = 0; i < body_pairs->count; i++) {
        int found = 0;
        for (int j = 0; j < entry_count; j++) {
            if (strcmp(entries[j].stem, body_pairs->pairs[i].stem) == 0) {
                entries[j].freq++;
                /* Keep longest original form (most readable) */
                if ((int)strlen(body_pairs->pairs[i].original) > (int)strlen(entries[j].original))
                    strcpy(entries[j].original, body_pairs->pairs[i].original);
                found = 1;
                break;
            }
        }
        if (!found && entry_count < MAX_TOKENS) {
            strcpy(entries[entry_count].stem, body_pairs->pairs[i].stem);
            strcpy(entries[entry_count].original, body_pairs->pairs[i].original);
            entries[entry_count].freq = 1;
            entries[entry_count].covered = 0;
            entry_count++;
        }
    }

    free(body_pairs);

    /* --- 5. Mark body terms covered by description + vocabulary --- */
    char covered_text[MAX_LINE * 2];
    snprintf(covered_text, sizeof(covered_text), "%s %s", description, vocabulary);
    TokenList *covered_tokens = calloc(1, sizeof(TokenList));
    if (!covered_tokens) { free(content); return 1; }
    tokenize(covered_text, covered_tokens);

    for (int i = 0; i < entry_count; i++) {
        for (int j = 0; j < covered_tokens->count; j++) {
            if (strcmp(entries[i].stem, covered_tokens->tokens[j]) == 0) {
                entries[i].covered = 1;
                break;
            }
        }
    }

    /* --- 6. Find vocabulary terms not appearing in body --- */
    typedef char WordBuf[MAX_TOKEN_LEN];
    WordBuf *vocab_words = calloc(MAX_TOKENS, sizeof(WordBuf));
    WordBuf *unused_words = calloc(MAX_TOKENS, sizeof(WordBuf));
    if (!vocab_words || !unused_words) {
        free(vocab_words); free(unused_words);
        free(entries); free(covered_tokens); free(content);
        return 1;
    }
    int vocab_word_count = 0;
    {
        char vocab_copy[MAX_LINE];
        strncpy(vocab_copy, vocabulary, sizeof(vocab_copy) - 1);
        vocab_copy[sizeof(vocab_copy) - 1] = '\0';
        char *tok = strtok(vocab_copy, " \t");
        while (tok && vocab_word_count < MAX_TOKENS) {
            strncpy(vocab_words[vocab_word_count], tok, MAX_TOKEN_LEN - 1);
            vocab_words[vocab_word_count][MAX_TOKEN_LEN - 1] = '\0';
            vocab_word_count++;
            tok = strtok(NULL, " \t");
        }
    }

    int unused_count = 0;
    for (int i = 0; i < vocab_word_count; i++) {
        char stemmed[MAX_TOKEN_LEN];
        strncpy(stemmed, vocab_words[i], MAX_TOKEN_LEN - 1);
        stemmed[MAX_TOKEN_LEN - 1] = '\0';
        int slen = strlen(stemmed);
        for (int j = 0; j < slen; j++) stemmed[j] = tolower((unsigned char)stemmed[j]);
        stem_word(stemmed, &slen);

        int in_body = 0;
        for (int j = 0; j < entry_count; j++) {
            if (strcmp(entries[j].stem, stemmed) == 0) {
                in_body = 1;
                break;
            }
        }
        if (!in_body) {
            strcpy(unused_words[unused_count++], vocab_words[i]);
        }
    }

    free(covered_tokens);

    /* --- 7. Sort entries by frequency descending --- */
    qsort(entries, entry_count, sizeof(SuggestEntry), cmp_suggest_freq);

    /* --- 8. Output report (machine-parseable sections) --- */

    /* Gaps: body terms not in description/vocabulary, above min_freq */
    int gap_count = 0;
    printf("GAPS\n");
    for (int i = 0; i < entry_count; i++) {
        if (!entries[i].covered && entries[i].freq >= min_freq) {
            printf("%s\t%d\t%s\n", entries[i].original, entries[i].freq, entries[i].stem);
            gap_count++;
        }
    }

    /* Coverage: vocabulary terms that appear in body */
    printf("COVERAGE\n");
    for (int i = 0; i < entry_count; i++) {
        if (entries[i].covered) {
            printf("%s\t%d\t%s\n", entries[i].original, entries[i].freq, entries[i].stem);
        }
    }

    /* Unused: vocabulary terms not found in body */
    printf("UNUSED\n");
    for (int i = 0; i < unused_count; i++) {
        printf("%s\n", unused_words[i]);
    }

    /* Suggested vocabulary line (current + gaps) */
    printf("VOCABULARY\n");
    printf("%s", vocabulary);
    for (int i = 0; i < entry_count; i++) {
        if (!entries[i].covered && entries[i].freq >= min_freq) {
            printf(" %s", entries[i].original);
        }
    }
    printf("\n");

    fprintf(stderr, "suggest: %d gaps (min_freq=%d), %d covered, %d unused\n",
            gap_count, min_freq, entry_count - gap_count, unused_count);

    free(vocab_words);
    free(unused_words);
    free(entries);
    free(content);
    return gap_count > 0 ? 0 : 1; /* exit 0 if suggestions exist, 1 if nothing to add */
}

/* ========================================================================
 * Usage and main
 * ======================================================================== */

static void usage(void) {
    fprintf(stderr,
        "way-match %s — BM25 semantic matcher for the ways system\n"
        "\n"
        "Usage:\n"
        "  way-match pair    --description DESC --vocabulary VOCAB --query Q [--threshold T]\n"
        "  way-match score   --corpus FILE --query Q [--threshold T]\n"
        "  way-match suggest --file FILE [--min-freq N]\n"
        "\n"
        "Pair mode:\n"
        "  Score a single description+vocabulary against a query.\n"
        "  Exit 0 if match (score >= threshold), 1 if no match.\n"
        "  Drop-in replacement for semantic-match.sh.\n"
        "\n"
        "Score mode:\n"
        "  Score all documents in a JSONL corpus against a query.\n"
        "  Output: id<TAB>score<TAB>description (ranked, above threshold only)\n"
        "\n"
        "Suggest mode:\n"
        "  Analyze a way.md file and suggest vocabulary improvements.\n"
        "  Compares body term frequencies against current description+vocabulary.\n"
        "  Output sections: GAPS, COVERAGE, UNUSED, VOCABULARY (tab-delimited).\n"
        "  Exit 0 if gaps found, 1 if vocabulary is complete.\n"
        "\n"
        "Options:\n"
        "  --description  Way description text\n"
        "  --vocabulary   Space-separated domain keywords\n"
        "  --query        User prompt to match against\n"
        "  --corpus       Path to JSONL corpus file\n"
        "  --file         Path to way.md file (suggest mode)\n"
        "  --threshold    Minimum score to match (default: 2.0)\n"
        "  --min-freq     Minimum term frequency for suggestions (default: 2)\n"
        "  --k1           BM25 k1 parameter (default: 1.2)\n"
        "  --b            BM25 b parameter (default: 0.75)\n"
        "  --version      Show version\n"
        "  --help         Show this help\n"
        , VERSION);
}

static const char *get_arg(int argc, char **argv, int i) {
    if (i + 1 >= argc) {
        fprintf(stderr, "error: %s requires a value\n", argv[i]);
        exit(1);
    }
    return argv[i + 1];
}

int main(int argc, char **argv) {
    if (argc < 2) {
        usage();
        return 1;
    }

    /* Check for --version or --help first */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--version") == 0) {
            printf("way-match %s\n", VERSION);
            return 0;
        }
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage();
            return 0;
        }
    }

    /* Initialize Snowball stemmer */
    stemmer_init();

    const char *command = argv[1];
    const char *description = NULL;
    const char *vocabulary = "";
    const char *query = NULL;
    const char *corpus_path = NULL;
    const char *filepath = NULL;
    double threshold = 2.0;
    int min_freq = 2;

    /* Parse arguments */
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--description") == 0) {
            description = get_arg(argc, argv, i); i++;
        } else if (strcmp(argv[i], "--vocabulary") == 0) {
            vocabulary = get_arg(argc, argv, i); i++;
        } else if (strcmp(argv[i], "--query") == 0) {
            query = get_arg(argc, argv, i); i++;
        } else if (strcmp(argv[i], "--corpus") == 0) {
            corpus_path = get_arg(argc, argv, i); i++;
        } else if (strcmp(argv[i], "--file") == 0) {
            filepath = get_arg(argc, argv, i); i++;
        } else if (strcmp(argv[i], "--threshold") == 0) {
            threshold = atof(get_arg(argc, argv, i)); i++;
        } else if (strcmp(argv[i], "--min-freq") == 0) {
            min_freq = atoi(get_arg(argc, argv, i)); i++;
        } else if (strcmp(argv[i], "--k1") == 0) {
            bm25_k1 = atof(get_arg(argc, argv, i)); i++;
        } else if (strcmp(argv[i], "--b") == 0) {
            bm25_b = atof(get_arg(argc, argv, i)); i++;
        } else {
            fprintf(stderr, "error: unknown option: %s\n", argv[i]);
            return 1;
        }
    }

    /* Dispatch */
    int result;
    if (strcmp(command, "pair") == 0) {
        if (!description || !query) {
            fprintf(stderr, "error: pair mode requires --description and --query\n");
            stemmer_cleanup();
            return 1;
        }
        result = cmd_pair(description, vocabulary, query, threshold);

    } else if (strcmp(command, "score") == 0) {
        if (!corpus_path || !query) {
            fprintf(stderr, "error: score mode requires --corpus and --query\n");
            stemmer_cleanup();
            return 1;
        }
        result = cmd_score(corpus_path, query, threshold);

    } else if (strcmp(command, "suggest") == 0) {
        if (!filepath) {
            fprintf(stderr, "error: suggest mode requires --file\n");
            stemmer_cleanup();
            return 1;
        }
        result = cmd_suggest(filepath, min_freq);

    } else {
        fprintf(stderr, "error: unknown command: %s (expected 'pair', 'score', or 'suggest')\n", command);
        stemmer_cleanup();
        return 1;
    }

    stemmer_cleanup();
    return result;
}
