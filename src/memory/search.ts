/**
 * Memory Search
 *
 * Full-text search functionality using FTS5.
 */

import type { MemoryDatabase } from './database.js';
import type {
  SearchResult,
  SearchOptions,
  FtsSearchRow,
  ObservationType,
} from './types.js';

/**
 * Search observations using FTS5
 */
export function searchObservations(
  database: MemoryDatabase,
  query: string,
  options: SearchOptions = {}
): SearchResult[] {
  const db = database.getDb();

  // Clean and prepare the query for FTS5
  const ftsQuery = prepareFtsQuery(query);

  if (!ftsQuery) {
    return [];
  }

  const limit = options.limit ?? 20;
  const offset = options.offset ?? 0;

  // Build additional filter conditions
  const conditions: string[] = [];
  const params: (string | number)[] = [ftsQuery];

  if (options.sessionId) {
    conditions.push('o.session_id = ?');
    params.push(options.sessionId);
  }

  if (options.workerId) {
    conditions.push('o.worker_id = ?');
    params.push(options.workerId);
  }

  if (options.type) {
    conditions.push('o.type = ?');
    params.push(options.type);
  }

  if (options.since) {
    conditions.push('o.created_at >= ?');
    params.push(options.since);
  }

  const additionalWhere = conditions.length > 0 ? `AND ${conditions.join(' AND ')}` : '';

  // Execute FTS5 search with ranking
  const sql = `
    SELECT
      o.*,
      fts.rank
    FROM observations_fts fts
    JOIN observations o ON o.id = fts.rowid
    WHERE observations_fts MATCH ?
    ${additionalWhere}
    ORDER BY fts.rank
    LIMIT ? OFFSET ?
  `;

  params.push(limit, offset);

  const rows = db.prepare(sql).all(...params) as FtsSearchRow[];

  return rows.map(row => ({
    observation: {
      id: row.id,
      sessionId: row.session_id,
      workerId: row.worker_id,
      type: row.type as ObservationType,
      content: row.content,
      metadata: row.metadata ? JSON.parse(row.metadata) : null,
      createdAt: row.created_at,
    },
    rank: row.rank,
    snippet: extractSnippet(row.content, query),
  }));
}

/**
 * Prepare query for FTS5
 * Handles special characters and creates a proper FTS5 query
 */
function prepareFtsQuery(query: string): string {
  // Remove special FTS5 characters that could cause issues
  const cleaned = query
    .replace(/[*:^~()]/g, ' ')
    .replace(/"/g, ' ')
    .trim();

  if (!cleaned) {
    return '';
  }

  // Split into words and add prefix matching
  const words = cleaned.split(/\s+/).filter(w => w.length > 0);

  if (words.length === 0) {
    return '';
  }

  // Use OR for multiple words, with prefix matching
  return words.map(w => `"${w}"*`).join(' OR ');
}

/**
 * Extract a snippet around the matched terms
 */
function extractSnippet(content: string, query: string, maxLength: number = 200): string {
  const lowerContent = content.toLowerCase();
  const queryWords = query.toLowerCase().split(/\s+/).filter(w => w.length > 2);

  if (queryWords.length === 0) {
    return content.slice(0, maxLength) + (content.length > maxLength ? '...' : '');
  }

  // Find the first occurrence of any query word
  let firstMatch = -1;
  for (const word of queryWords) {
    const idx = lowerContent.indexOf(word);
    if (idx !== -1 && (firstMatch === -1 || idx < firstMatch)) {
      firstMatch = idx;
    }
  }

  if (firstMatch === -1) {
    // No match found, return beginning of content
    return content.slice(0, maxLength) + (content.length > maxLength ? '...' : '');
  }

  // Calculate snippet window
  const contextBefore = 40;
  const contextAfter = maxLength - contextBefore;

  const start = Math.max(0, firstMatch - contextBefore);
  const end = Math.min(content.length, firstMatch + contextAfter);

  let snippet = content.slice(start, end);

  // Add ellipsis if truncated
  if (start > 0) {
    snippet = '...' + snippet;
  }
  if (end < content.length) {
    snippet = snippet + '...';
  }

  return snippet;
}

/**
 * Get search suggestions based on existing content
 */
export function getSearchSuggestions(
  database: MemoryDatabase,
  prefix: string,
  limit: number = 5
): string[] {
  if (!prefix || prefix.length < 2) {
    return [];
  }

  const db = database.getDb();

  // Get unique words from observations that match the prefix
  const sql = `
    SELECT DISTINCT content
    FROM observations
    WHERE content LIKE ?
    LIMIT ?
  `;

  const rows = db.prepare(sql).all(`%${prefix}%`, limit * 10) as { content: string }[];

  // Extract matching words
  const prefixLower = prefix.toLowerCase();
  const words = new Set<string>();

  for (const row of rows) {
    const contentWords = row.content.split(/\s+/);
    for (const word of contentWords) {
      const cleanWord = word.toLowerCase().replace(/[^a-z0-9]/g, '');
      if (cleanWord.startsWith(prefixLower) && cleanWord.length > prefix.length) {
        words.add(cleanWord);
        if (words.size >= limit) {
          break;
        }
      }
    }
    if (words.size >= limit) {
      break;
    }
  }

  return Array.from(words).slice(0, limit);
}

/**
 * Get summary of search results
 */
export function getSearchSummary(results: SearchResult[]): {
  totalResults: number;
  workerIds: string[];
  types: ObservationType[];
  dateRange: { earliest: string; latest: string } | null;
} {
  if (results.length === 0) {
    return {
      totalResults: 0,
      workerIds: [],
      types: [],
      dateRange: null,
    };
  }

  const workerIds = [...new Set(results.map(r => r.observation.workerId))];
  const types = [...new Set(results.map(r => r.observation.type))];

  const dates = results.map(r => r.observation.createdAt).sort();

  return {
    totalResults: results.length,
    workerIds,
    types,
    dateRange: {
      earliest: dates[0],
      latest: dates[dates.length - 1],
    },
  };
}
