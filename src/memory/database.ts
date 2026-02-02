/**
 * Memory Database
 *
 * SQLite database initialization and schema management for the memory system.
 * Uses better-sqlite3 for synchronous operations.
 */

import Database from 'better-sqlite3';
import * as path from 'node:path';
import * as fs from 'node:fs';
import type { Logger } from '../types.js';

/** Current schema version for migrations */
export const SCHEMA_VERSION = 1;

/**
 * Database initialization options
 */
export interface DatabaseOptions {
  dataDir: string;
  dbPath?: string;
  logger?: Logger;
}

/**
 * Database class for memory persistence
 */
export class MemoryDatabase {
  private db: Database.Database | null = null;
  private readonly dbPath: string;
  private readonly logger?: Logger;

  constructor(options: DatabaseOptions) {
    this.dbPath = options.dbPath ?? path.join(options.dataDir, 'memory.db');
    this.logger = options.logger;

    // Ensure data directory exists
    const dir = path.dirname(this.dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  /**
   * Initialize the database connection and run migrations
   */
  initialize(): void {
    if (this.db) {
      return;
    }

    this.logger?.debug?.('Initializing memory database', { path: this.dbPath });

    this.db = new Database(this.dbPath);

    // Enable WAL mode for better concurrency
    this.db.pragma('journal_mode = WAL');

    // Run migrations
    this.migrate();

    this.logger?.info?.('Memory database initialized', { path: this.dbPath });
  }

  /**
   * Close the database connection
   */
  close(): void {
    if (this.db) {
      this.db.close();
      this.db = null;
      this.logger?.debug?.('Memory database closed');
    }
  }

  /**
   * Get the database instance (throws if not initialized)
   */
  getDb(): Database.Database {
    if (!this.db) {
      throw new Error('Database not initialized. Call initialize() first.');
    }
    return this.db;
  }

  /**
   * Check if database is initialized
   */
  isInitialized(): boolean {
    return this.db !== null;
  }

  /**
   * Run database migrations
   */
  private migrate(): void {
    const db = this.getDb();

    // Create migrations table
    db.exec(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      );
    `);

    // Get current version
    const row = db.prepare('SELECT MAX(version) as version FROM schema_migrations').get() as { version: number | null };
    const currentVersion = row?.version ?? 0;

    this.logger?.debug?.('Current schema version', { version: currentVersion });

    // Apply migrations
    if (currentVersion < 1) {
      this.migrateV1();
    }
  }

  /**
   * Migration V1: Initial schema
   */
  private migrateV1(): void {
    const db = this.getDb();

    this.logger?.info?.('Applying migration v1');

    db.exec(`
      -- Sessions table (orchestrator sessions)
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        worker_count INTEGER DEFAULT 0,
        summary TEXT,
        metadata TEXT
      );

      -- Observations table
      CREATE TABLE IF NOT EXISTS observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        worker_id TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        metadata TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      );

      -- Create indexes for common queries
      CREATE INDEX IF NOT EXISTS idx_observations_session_id ON observations(session_id);
      CREATE INDEX IF NOT EXISTS idx_observations_worker_id ON observations(worker_id);
      CREATE INDEX IF NOT EXISTS idx_observations_type ON observations(type);
      CREATE INDEX IF NOT EXISTS idx_observations_created_at ON observations(created_at);

      -- Summaries table (compressed session summaries)
      CREATE TABLE IF NOT EXISTS summaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        summary TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      );

      CREATE INDEX IF NOT EXISTS idx_summaries_session_id ON summaries(session_id);

      -- Full-text search virtual table
      CREATE VIRTUAL TABLE IF NOT EXISTS observations_fts USING fts5(
        content,
        content=observations,
        content_rowid=id
      );

      -- Triggers to keep FTS index in sync
      CREATE TRIGGER IF NOT EXISTS observations_ai AFTER INSERT ON observations BEGIN
        INSERT INTO observations_fts(rowid, content) VALUES (new.id, new.content);
      END;

      CREATE TRIGGER IF NOT EXISTS observations_ad AFTER DELETE ON observations BEGIN
        INSERT INTO observations_fts(observations_fts, rowid, content) VALUES('delete', old.id, old.content);
      END;

      CREATE TRIGGER IF NOT EXISTS observations_au AFTER UPDATE ON observations BEGIN
        INSERT INTO observations_fts(observations_fts, rowid, content) VALUES('delete', old.id, old.content);
        INSERT INTO observations_fts(rowid, content) VALUES (new.id, new.content);
      END;

      -- Record migration
      INSERT INTO schema_migrations (version, applied_at) VALUES (1, datetime('now'));
    `);

    this.logger?.info?.('Migration v1 applied successfully');
  }

  /**
   * Get database stats
   */
  getStats(): { sessions: number; observations: number; summaries: number; sizeBytes: number } {
    const db = this.getDb();

    const sessions = (db.prepare('SELECT COUNT(*) as count FROM sessions').get() as { count: number }).count;
    const observations = (db.prepare('SELECT COUNT(*) as count FROM observations').get() as { count: number }).count;
    const summaries = (db.prepare('SELECT COUNT(*) as count FROM summaries').get() as { count: number }).count;

    let sizeBytes = 0;
    try {
      const stats = fs.statSync(this.dbPath);
      sizeBytes = stats.size;
    } catch {
      // Ignore
    }

    return { sessions, observations, summaries, sizeBytes };
  }

  /**
   * Vacuum the database to reclaim space
   */
  vacuum(): void {
    const db = this.getDb();
    db.exec('VACUUM');
    this.logger?.info?.('Database vacuumed');
  }

  /**
   * Rebuild FTS index
   */
  rebuildFtsIndex(): void {
    const db = this.getDb();
    db.exec("INSERT INTO observations_fts(observations_fts) VALUES('rebuild')");
    this.logger?.info?.('FTS index rebuilt');
  }
}
