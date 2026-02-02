/**
 * Observation Store
 *
 * CRUD operations for worker observations.
 */

import type { MemoryDatabase } from './database.js';
import type {
  Observation,
  NewObservation,
  ObservationRow,
  ObservationFilter,
  ObservationType,
} from './types.js';

/**
 * Convert database row to Observation object
 */
function rowToObservation(row: ObservationRow): Observation {
  return {
    id: row.id,
    sessionId: row.session_id,
    workerId: row.worker_id,
    type: row.type as ObservationType,
    content: row.content,
    metadata: row.metadata ? JSON.parse(row.metadata) : null,
    createdAt: row.created_at,
  };
}

/**
 * Store for managing worker observations
 */
export class ObservationStore {
  constructor(private readonly database: MemoryDatabase) {}

  /**
   * Add a new observation
   */
  add(input: NewObservation): Observation {
    const db = this.database.getDb();
    const createdAt = new Date().toISOString();
    const metadata = input.metadata ? JSON.stringify(input.metadata) : null;

    const result = db.prepare(`
      INSERT INTO observations (session_id, worker_id, type, content, metadata, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(input.sessionId, input.workerId, input.type, input.content, metadata, createdAt);

    return {
      id: result.lastInsertRowid as number,
      sessionId: input.sessionId,
      workerId: input.workerId,
      type: input.type,
      content: input.content,
      metadata: input.metadata ?? null,
      createdAt,
    };
  }

  /**
   * Get observation by ID
   */
  getById(id: number): Observation | null {
    const db = this.database.getDb();
    const row = db.prepare('SELECT * FROM observations WHERE id = ?').get(id) as ObservationRow | undefined;
    return row ? rowToObservation(row) : null;
  }

  /**
   * Get observations by worker ID
   */
  getByWorkerId(workerId: string, limit: number = 100): Observation[] {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT * FROM observations
      WHERE worker_id = ?
      ORDER BY created_at DESC
      LIMIT ?
    `).all(workerId, limit) as ObservationRow[];

    return rows.map(rowToObservation);
  }

  /**
   * Get observations by session ID
   */
  getBySessionId(sessionId: string, limit: number = 100): Observation[] {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT * FROM observations
      WHERE session_id = ?
      ORDER BY created_at DESC
      LIMIT ?
    `).all(sessionId, limit) as ObservationRow[];

    return rows.map(rowToObservation);
  }

  /**
   * Get observations by type
   */
  getByType(type: ObservationType, limit: number = 100): Observation[] {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT * FROM observations
      WHERE type = ?
      ORDER BY created_at DESC
      LIMIT ?
    `).all(type, limit) as ObservationRow[];

    return rows.map(rowToObservation);
  }

  /**
   * Get observations with flexible filtering
   */
  getFiltered(filter: ObservationFilter): Observation[] {
    const db = this.database.getDb();

    const conditions: string[] = [];
    const params: (string | number)[] = [];

    if (filter.sessionId) {
      conditions.push('session_id = ?');
      params.push(filter.sessionId);
    }

    if (filter.workerId) {
      conditions.push('worker_id = ?');
      params.push(filter.workerId);
    }

    if (filter.type) {
      conditions.push('type = ?');
      params.push(filter.type);
    }

    if (filter.since) {
      conditions.push('created_at >= ?');
      params.push(filter.since);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const limit = filter.limit ?? 100;
    const offset = filter.offset ?? 0;

    const sql = `
      SELECT * FROM observations
      ${whereClause}
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;

    const rows = db.prepare(sql).all(...params, limit, offset) as ObservationRow[];
    return rows.map(rowToObservation);
  }

  /**
   * Get multiple observations by IDs
   */
  getByIds(ids: number[]): Observation[] {
    if (ids.length === 0) {
      return [];
    }

    const db = this.database.getDb();
    const placeholders = ids.map(() => '?').join(', ');
    const rows = db.prepare(`
      SELECT * FROM observations
      WHERE id IN (${placeholders})
      ORDER BY created_at DESC
    `).all(...ids) as ObservationRow[];

    return rows.map(rowToObservation);
  }

  /**
   * Delete an observation
   */
  delete(id: number): boolean {
    const db = this.database.getDb();
    const result = db.prepare('DELETE FROM observations WHERE id = ?').run(id);
    return result.changes > 0;
  }

  /**
   * Delete observations for a worker
   */
  deleteByWorkerId(workerId: string): number {
    const db = this.database.getDb();
    const result = db.prepare('DELETE FROM observations WHERE worker_id = ?').run(workerId);
    return result.changes;
  }

  /**
   * Count observations
   */
  count(filter?: { sessionId?: string; workerId?: string; type?: ObservationType }): number {
    const db = this.database.getDb();

    const conditions: string[] = [];
    const params: string[] = [];

    if (filter?.sessionId) {
      conditions.push('session_id = ?');
      params.push(filter.sessionId);
    }

    if (filter?.workerId) {
      conditions.push('worker_id = ?');
      params.push(filter.workerId);
    }

    if (filter?.type) {
      conditions.push('type = ?');
      params.push(filter.type);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const row = db.prepare(`
      SELECT COUNT(*) as count FROM observations ${whereClause}
    `).get(...params) as { count: number };

    return row.count;
  }

  /**
   * Get recent observations
   */
  getRecent(limit: number = 50): Observation[] {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT * FROM observations
      ORDER BY created_at DESC
      LIMIT ?
    `).all(limit) as ObservationRow[];

    return rows.map(rowToObservation);
  }

  /**
   * Get unique worker IDs
   */
  getUniqueWorkerIds(): string[] {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT DISTINCT worker_id FROM observations
      ORDER BY worker_id
    `).all() as { worker_id: string }[];

    return rows.map(r => r.worker_id);
  }

  /**
   * Get observation timeline for a session
   */
  getTimeline(sessionId: string): Array<{ workerId: string; type: ObservationType; content: string; createdAt: string }> {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT worker_id, type, content, created_at
      FROM observations
      WHERE session_id = ?
      ORDER BY created_at ASC
    `).all(sessionId) as Array<{ worker_id: string; type: string; content: string; created_at: string }>;

    return rows.map(r => ({
      workerId: r.worker_id,
      type: r.type as ObservationType,
      content: r.content,
      createdAt: r.created_at,
    }));
  }
}
