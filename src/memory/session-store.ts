/**
 * Session Store
 *
 * CRUD operations for orchestrator sessions.
 */

import { randomUUID } from 'node:crypto';
import type { MemoryDatabase } from './database.js';
import type {
  Session,
  NewSession,
  SessionRow,
} from './types.js';

/**
 * Convert database row to Session object
 */
function rowToSession(row: SessionRow): Session {
  return {
    id: row.id,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    workerCount: row.worker_count,
    summary: row.summary,
    metadata: row.metadata ? JSON.parse(row.metadata) : null,
  };
}

/**
 * Store for managing orchestrator sessions
 */
export class SessionStore {
  constructor(private readonly database: MemoryDatabase) {}

  /**
   * Create a new session
   */
  create(input: NewSession = {}): Session {
    const db = this.database.getDb();
    const id = input.id ?? randomUUID();
    const startedAt = new Date().toISOString();
    const metadata = input.metadata ? JSON.stringify(input.metadata) : null;

    db.prepare(`
      INSERT INTO sessions (id, started_at, worker_count, metadata)
      VALUES (?, ?, 0, ?)
    `).run(id, startedAt, metadata);

    return {
      id,
      startedAt,
      endedAt: null,
      workerCount: 0,
      summary: null,
      metadata: input.metadata ?? null,
    };
  }

  /**
   * Get session by ID
   */
  getById(id: string): Session | null {
    const db = this.database.getDb();
    const row = db.prepare('SELECT * FROM sessions WHERE id = ?').get(id) as SessionRow | undefined;
    return row ? rowToSession(row) : null;
  }

  /**
   * Update session
   */
  update(id: string, updates: Partial<Pick<Session, 'workerCount' | 'summary' | 'metadata'>>): Session | null {
    const db = this.database.getDb();

    const existing = this.getById(id);
    if (!existing) {
      return null;
    }

    const workerCount = updates.workerCount ?? existing.workerCount;
    const summary = updates.summary ?? existing.summary;
    const metadata = updates.metadata !== undefined
      ? JSON.stringify(updates.metadata)
      : (existing.metadata ? JSON.stringify(existing.metadata) : null);

    db.prepare(`
      UPDATE sessions
      SET worker_count = ?, summary = ?, metadata = ?
      WHERE id = ?
    `).run(workerCount, summary, metadata, id);

    return this.getById(id);
  }

  /**
   * End a session
   */
  endSession(id: string, summary?: string): Session | null {
    const db = this.database.getDb();

    const existing = this.getById(id);
    if (!existing) {
      return null;
    }

    const endedAt = new Date().toISOString();

    db.prepare(`
      UPDATE sessions
      SET ended_at = ?, summary = COALESCE(?, summary)
      WHERE id = ?
    `).run(endedAt, summary ?? null, id);

    return this.getById(id);
  }

  /**
   * Increment worker count
   */
  incrementWorkerCount(id: string): void {
    const db = this.database.getDb();
    db.prepare(`
      UPDATE sessions
      SET worker_count = worker_count + 1
      WHERE id = ?
    `).run(id);
  }

  /**
   * Get recent sessions
   */
  getRecent(limit: number = 10): Session[] {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT * FROM sessions
      ORDER BY started_at DESC
      LIMIT ?
    `).all(limit) as SessionRow[];

    return rows.map(rowToSession);
  }

  /**
   * Get active sessions (not ended)
   */
  getActive(): Session[] {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT * FROM sessions
      WHERE ended_at IS NULL
      ORDER BY started_at DESC
    `).all() as SessionRow[];

    return rows.map(rowToSession);
  }

  /**
   * Delete a session and all its observations
   */
  delete(id: string): boolean {
    const db = this.database.getDb();

    // Delete observations first (cascading)
    db.prepare('DELETE FROM observations WHERE session_id = ?').run(id);
    db.prepare('DELETE FROM summaries WHERE session_id = ?').run(id);

    const result = db.prepare('DELETE FROM sessions WHERE id = ?').run(id);
    return result.changes > 0;
  }

  /**
   * Count total sessions
   */
  count(): number {
    const db = this.database.getDb();
    const row = db.prepare('SELECT COUNT(*) as count FROM sessions').get() as { count: number };
    return row.count;
  }

  /**
   * Clean up old sessions (older than given days)
   */
  cleanup(olderThanDays: number = 30): number {
    const db = this.database.getDb();
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - olderThanDays);
    const cutoffIso = cutoff.toISOString();

    // Get session IDs to delete
    const sessions = db.prepare(`
      SELECT id FROM sessions
      WHERE ended_at IS NOT NULL AND ended_at < ?
    `).all(cutoffIso) as { id: string }[];

    // Delete each session
    for (const session of sessions) {
      this.delete(session.id);
    }

    return sessions.length;
  }
}
