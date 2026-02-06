/**
 * Backlog Store
 *
 * CRUD operations for the tasks backlog.
 * Stores suggestions, important issues, and future work items.
 */

import type { MemoryDatabase } from './database.js';
import type {
  BacklogTask,
  NewBacklogTask,
  BacklogFilter,
  BacklogTaskRow,
  BacklogPriority,
  BacklogStatus,
  BacklogSource,
} from './types.js';

/**
 * Convert database row to BacklogTask object
 */
function rowToBacklogTask(row: BacklogTaskRow): BacklogTask {
  return {
    id: row.id,
    source: row.source as BacklogSource,
    priority: row.priority as BacklogPriority,
    title: row.title,
    description: row.description,
    filePath: row.file_path,
    lineNumber: row.line_number,
    status: row.status as BacklogStatus,
    createdAt: row.created_at,
    completedAt: row.completed_at,
    metadata: row.metadata ? JSON.parse(row.metadata) : null,
  };
}

/**
 * Store for managing the tasks backlog
 */
export class BacklogStore {
  constructor(private readonly database: MemoryDatabase) {}

  /**
   * Add a new task to the backlog
   */
  add(input: NewBacklogTask): BacklogTask {
    const db = this.database.getDb();
    const createdAt = new Date().toISOString();
    const metadata = input.metadata ? JSON.stringify(input.metadata) : null;

    const result = db.prepare(`
      INSERT INTO tasks_backlog (source, priority, title, description, file_path, line_number, status, created_at, metadata)
      VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
    `).run(
      input.source,
      input.priority,
      input.title,
      input.description ?? null,
      input.filePath ?? null,
      input.lineNumber ?? null,
      createdAt,
      metadata
    );

    return {
      id: result.lastInsertRowid as number,
      source: input.source,
      priority: input.priority,
      title: input.title,
      description: input.description ?? null,
      filePath: input.filePath ?? null,
      lineNumber: input.lineNumber ?? null,
      status: 'pending',
      createdAt,
      completedAt: null,
      metadata: input.metadata ?? null,
    };
  }

  /**
   * Get task by ID
   */
  getById(id: number): BacklogTask | null {
    const db = this.database.getDb();
    const row = db.prepare('SELECT * FROM tasks_backlog WHERE id = ?').get(id) as BacklogTaskRow | undefined;
    return row ? rowToBacklogTask(row) : null;
  }

  /**
   * List tasks with optional filtering
   */
  list(filter: BacklogFilter = {}): BacklogTask[] {
    const db = this.database.getDb();

    const conditions: string[] = ["status != 'deleted'"];
    const params: unknown[] = [];

    if (filter.source) {
      conditions.push('source = ?');
      params.push(filter.source);
    }

    if (filter.priority) {
      conditions.push('priority = ?');
      params.push(filter.priority);
    }

    if (filter.status) {
      conditions.push('status = ?');
      params.push(filter.status);
    }

    if (filter.since) {
      conditions.push('created_at >= ?');
      params.push(filter.since);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const limitClause = filter.limit ? `LIMIT ${filter.limit}` : '';
    const offsetClause = filter.offset ? `OFFSET ${filter.offset}` : '';

    const rows = db.prepare(`
      SELECT * FROM tasks_backlog
      ${whereClause}
      ORDER BY
        CASE priority
          WHEN 'critical' THEN 1
          WHEN 'important' THEN 2
          WHEN 'suggestion' THEN 3
        END,
        created_at DESC
      ${limitClause} ${offsetClause}
    `).all(...params) as BacklogTaskRow[];

    return rows.map(rowToBacklogTask);
  }

  /**
   * Get pending tasks (not completed or deleted)
   */
  getPending(limit?: number): BacklogTask[] {
    return this.list({ status: 'pending', limit });
  }

  /**
   * Get tasks by priority
   */
  getByPriority(priority: BacklogPriority, limit?: number): BacklogTask[] {
    return this.list({ priority, limit });
  }

  /**
   * Get tasks by source
   */
  getBySource(source: BacklogSource, limit?: number): BacklogTask[] {
    return this.list({ source, limit });
  }

  /**
   * Update a task's status
   */
  updateStatus(id: number, status: BacklogStatus): BacklogTask | null {
    const db = this.database.getDb();

    const existing = this.getById(id);
    if (!existing) {
      return null;
    }

    const completedAt = status === 'completed' ? new Date().toISOString() : null;

    db.prepare(`
      UPDATE tasks_backlog
      SET status = ?, completed_at = ?
      WHERE id = ?
    `).run(status, completedAt, id);

    return this.getById(id);
  }

  /**
   * Mark a task as completed
   */
  complete(id: number): BacklogTask | null {
    return this.updateStatus(id, 'completed');
  }

  /**
   * Mark a task as in progress
   */
  startProgress(id: number): BacklogTask | null {
    return this.updateStatus(id, 'in_progress');
  }

  /**
   * Soft delete a task (marks as deleted, doesn't remove from DB)
   */
  delete(id: number): boolean {
    const result = this.updateStatus(id, 'deleted');
    return result !== null;
  }

  /**
   * Hard delete a task (removes from DB)
   */
  hardDelete(id: number): boolean {
    const db = this.database.getDb();
    const result = db.prepare('DELETE FROM tasks_backlog WHERE id = ?').run(id);
    return result.changes > 0;
  }

  /**
   * Update task details
   */
  update(id: number, updates: Partial<Pick<BacklogTask, 'title' | 'description' | 'priority' | 'filePath' | 'lineNumber' | 'metadata'>>): BacklogTask | null {
    const db = this.database.getDb();

    const existing = this.getById(id);
    if (!existing) {
      return null;
    }

    const title = updates.title ?? existing.title;
    const description = updates.description ?? existing.description;
    const priority = updates.priority ?? existing.priority;
    const filePath = updates.filePath ?? existing.filePath;
    const lineNumber = updates.lineNumber ?? existing.lineNumber;
    const metadata = updates.metadata !== undefined
      ? JSON.stringify(updates.metadata)
      : (existing.metadata ? JSON.stringify(existing.metadata) : null);

    db.prepare(`
      UPDATE tasks_backlog
      SET title = ?, description = ?, priority = ?, file_path = ?, line_number = ?, metadata = ?
      WHERE id = ?
    `).run(title, description, priority, filePath, lineNumber, metadata, id);

    return this.getById(id);
  }

  /**
   * Search backlog tasks using full-text search
   */
  search(query: string, limit: number = 50): BacklogTask[] {
    const db = this.database.getDb();

    // Escape special FTS5 characters
    const escapedQuery = query.replace(/['"]/g, '');

    const rows = db.prepare(`
      SELECT t.*
      FROM tasks_backlog t
      JOIN backlog_fts f ON t.id = f.rowid
      WHERE backlog_fts MATCH ? AND t.status != 'deleted'
      ORDER BY rank
      LIMIT ?
    `).all(escapedQuery, limit) as BacklogTaskRow[];

    return rows.map(rowToBacklogTask);
  }

  /**
   * Count tasks by status
   */
  countByStatus(): Record<BacklogStatus, number> {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT status, COUNT(*) as count
      FROM tasks_backlog
      GROUP BY status
    `).all() as Array<{ status: string; count: number }>;

    const result: Record<BacklogStatus, number> = {
      pending: 0,
      in_progress: 0,
      completed: 0,
      deleted: 0,
    };

    for (const row of rows) {
      result[row.status as BacklogStatus] = row.count;
    }

    return result;
  }

  /**
   * Count tasks by priority (excluding deleted)
   */
  countByPriority(): Record<BacklogPriority, number> {
    const db = this.database.getDb();
    const rows = db.prepare(`
      SELECT priority, COUNT(*) as count
      FROM tasks_backlog
      WHERE status != 'deleted'
      GROUP BY priority
    `).all() as Array<{ priority: string; count: number }>;

    const result: Record<BacklogPriority, number> = {
      critical: 0,
      important: 0,
      suggestion: 0,
    };

    for (const row of rows) {
      result[row.priority as BacklogPriority] = row.count;
    }

    return result;
  }

  /**
   * Get statistics about the backlog
   */
  getStats(): {
    total: number;
    byStatus: Record<BacklogStatus, number>;
    byPriority: Record<BacklogPriority, number>;
    bySource: Record<BacklogSource, number>;
  } {
    const db = this.database.getDb();

    const total = (db.prepare("SELECT COUNT(*) as count FROM tasks_backlog WHERE status != 'deleted'").get() as { count: number }).count;
    const byStatus = this.countByStatus();
    const byPriority = this.countByPriority();

    const sourceRows = db.prepare(`
      SELECT source, COUNT(*) as count
      FROM tasks_backlog
      WHERE status != 'deleted'
      GROUP BY source
    `).all() as Array<{ source: string; count: number }>;

    const bySource: Record<BacklogSource, number> = {
      project: 0,
      review: 0,
      manual: 0,
    };

    for (const row of sourceRows) {
      bySource[row.source as BacklogSource] = row.count;
    }

    return { total, byStatus, byPriority, bySource };
  }

  /**
   * Clean up completed tasks older than given days
   */
  cleanup(olderThanDays: number = 90): number {
    const db = this.database.getDb();
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - olderThanDays);
    const cutoffIso = cutoff.toISOString();

    const result = db.prepare(`
      DELETE FROM tasks_backlog
      WHERE status = 'completed' AND completed_at < ?
    `).run(cutoffIso);

    return result.changes;
  }
}
