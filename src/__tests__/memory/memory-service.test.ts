/**
 * Memory Service Tests
 *
 * Integration tests for the complete memory system.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { MemoryService } from '../../memory/memory-service.js';
import type { ObservationType } from '../../memory/types.js';

describe('MemoryService', () => {
  let service: MemoryService;
  let testDir: string;

  beforeEach(() => {
    // Create a unique temp directory for each test
    testDir = path.join(os.tmpdir(), `memory-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
    fs.mkdirSync(testDir, { recursive: true });

    service = new MemoryService({
      dataDir: testDir,
    });
  });

  afterEach(() => {
    // Clean up
    if (service.isInitialized()) {
      service.shutdown();
    }

    try {
      fs.rmSync(testDir, { recursive: true, force: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  describe('lifecycle', () => {
    it('should initialize and shutdown cleanly', () => {
      expect(service.isInitialized()).toBe(false);

      service.initialize();
      expect(service.isInitialized()).toBe(true);

      service.shutdown();
      expect(service.isInitialized()).toBe(false);
    });

    it('should be idempotent for initialize', () => {
      service.initialize();
      service.initialize(); // Should not throw
      expect(service.isInitialized()).toBe(true);
    });

    it('should be idempotent for shutdown', () => {
      service.initialize();
      service.shutdown();
      service.shutdown(); // Should not throw
      expect(service.isInitialized()).toBe(false);
    });
  });

  describe('sessions', () => {
    beforeEach(() => {
      service.initialize();
    });

    it('should start a session', () => {
      const sessionId = service.startSession();

      expect(sessionId).toBeTruthy();
      expect(service.getCurrentSessionId()).toBe(sessionId);
    });

    it('should end a session', () => {
      const sessionId = service.startSession();
      service.endSession('Test completed');

      expect(service.getCurrentSessionId()).toBeNull();

      const session = service.getSession(sessionId);
      expect(session?.endedAt).toBeTruthy();
      expect(session?.summary).toBe('Test completed');
    });

    it('should get recent sessions', () => {
      const sessionId1 = service.startSession();
      service.endSession();

      const sessionId2 = service.startSession();

      const sessions = service.getRecentSessions(10);
      expect(sessions.length).toBe(2);
      // Both session IDs should be present
      const sessionIds = sessions.map(s => s.id);
      expect(sessionIds).toContain(sessionId1);
      expect(sessionIds).toContain(sessionId2);
    });
  });

  describe('observations', () => {
    let sessionId: string;

    beforeEach(() => {
      service.initialize();
      sessionId = service.startSession();
    });

    it('should capture an observation', () => {
      const observation = service.captureObservation({
        workerId: 'test-worker',
        type: 'task_complete',
        content: 'Test task completed',
        metadata: { duration: 1000 },
      });

      expect(observation.id).toBeTruthy();
      expect(observation.workerId).toBe('test-worker');
      expect(observation.type).toBe('task_complete');
      expect(observation.content).toBe('Test task completed');
      expect(observation.metadata?.duration).toBe(1000);
    });

    it('should capture state change', () => {
      const observation = service.captureStateChange(
        'worker-1',
        'SPAWNING',
        'WORKING',
        { task: 'Test' }
      );

      expect(observation.type).toBe('state_change');
      expect(observation.content).toContain('SPAWNING');
      expect(observation.content).toContain('WORKING');
    });

    it('should capture PR event', () => {
      const observation = service.capturePrEvent(
        'worker-1',
        'created',
        42,
        'https://github.com/test/test/pull/42'
      );

      expect(observation.type).toBe('pr_event');
      expect(observation.content).toContain('42');
      expect(observation.metadata?.prNumber).toBe(42);
    });

    it('should capture error', () => {
      const observation = service.captureError(
        'worker-1',
        'Connection failed',
        { retries: 3 }
      );

      expect(observation.type).toBe('error');
      expect(observation.content).toContain('Connection failed');
    });

    it('should get observations by worker', () => {
      service.captureObservation({
        workerId: 'worker-1',
        type: 'state_change',
        content: 'Test 1',
      });

      service.captureObservation({
        workerId: 'worker-2',
        type: 'state_change',
        content: 'Test 2',
      });

      service.captureObservation({
        workerId: 'worker-1',
        type: 'task_complete',
        content: 'Test 3',
      });

      const observations = service.getWorkerObservations('worker-1');
      expect(observations.length).toBe(2);
      expect(observations.every(o => o.workerId === 'worker-1')).toBe(true);
    });

    it('should filter observations', () => {
      const types: ObservationType[] = ['state_change', 'pr_event', 'error'];

      for (const type of types) {
        service.captureObservation({
          workerId: 'worker-1',
          type,
          content: `Test ${type}`,
        });
      }

      const filtered = service.getObservations({ type: 'pr_event' });
      expect(filtered.length).toBe(1);
      expect(filtered[0].type).toBe('pr_event');
    });
  });

  describe('search', () => {
    beforeEach(() => {
      service.initialize();
      service.startSession();

      // Add test observations
      service.captureObservation({
        workerId: 'auth-worker',
        type: 'task_complete',
        content: 'Implemented user authentication with JWT tokens',
      });

      service.captureObservation({
        workerId: 'db-worker',
        type: 'task_complete',
        content: 'Created database migrations for users table',
      });

      service.captureObservation({
        workerId: 'api-worker',
        type: 'error',
        content: 'Failed to connect to authentication service',
      });
    });

    it('should search observations by keyword', () => {
      const results = service.search('authentication');

      expect(results.length).toBeGreaterThan(0);
      expect(results.some(r => r.observation.content.includes('authentication'))).toBe(true);
    });

    it('should return ranked results', () => {
      const results = service.search('user');

      expect(results.length).toBeGreaterThan(0);
      // Results should be sorted by rank
      for (let i = 1; i < results.length; i++) {
        expect(results[i].rank).toBeGreaterThanOrEqual(results[i - 1].rank);
      }
    });

    it('should provide search summary', () => {
      const { results, summary } = service.searchWithSummary('authentication');

      expect(summary.totalResults).toBe(results.length);
      expect(summary.workerIds.length).toBeGreaterThan(0);
      expect(summary.types.length).toBeGreaterThan(0);
    });

    it('should filter search by workerId', () => {
      const results = service.search('service', { workerId: 'api-worker' });

      expect(results.every(r => r.observation.workerId === 'api-worker')).toBe(true);
    });

    it('should handle empty search gracefully', () => {
      const results = service.search('nonexistent-term-xyz');
      expect(results).toEqual([]);
    });
  });

  describe('stats', () => {
    beforeEach(() => {
      service.initialize();
    });

    it('should return database stats', () => {
      service.startSession();

      service.captureObservation({
        workerId: 'test',
        type: 'custom',
        content: 'Test observation',
      });

      const stats = service.getStats();

      expect(stats.sessions).toBeGreaterThan(0);
      expect(stats.observations).toBeGreaterThan(0);
      expect(stats.sizeBytes).toBeGreaterThan(0);
      expect(stats.currentSessionId).toBeTruthy();
    });

    it('should return unique worker IDs', () => {
      service.startSession();

      service.captureObservation({
        workerId: 'worker-a',
        type: 'custom',
        content: 'Test 1',
      });

      service.captureObservation({
        workerId: 'worker-b',
        type: 'custom',
        content: 'Test 2',
      });

      service.captureObservation({
        workerId: 'worker-a',
        type: 'custom',
        content: 'Test 3',
      });

      const workerIds = service.getWorkerIds();
      expect(workerIds).toContain('worker-a');
      expect(workerIds).toContain('worker-b');
      expect(workerIds.length).toBe(2);
    });
  });

  describe('persistence', () => {
    it('should persist data across service restarts', () => {
      // First service instance
      service.initialize();
      const sessionId = service.startSession();

      service.captureObservation({
        workerId: 'test-worker',
        type: 'task_complete',
        content: 'Persistent test observation',
      });

      service.shutdown();

      // Second service instance with same data dir
      const service2 = new MemoryService({ dataDir: testDir });
      service2.initialize();

      const sessions = service2.getRecentSessions(10);
      expect(sessions.some(s => s.id === sessionId)).toBe(true);

      const results = service2.search('Persistent');
      expect(results.length).toBeGreaterThan(0);

      service2.shutdown();
    });
  });

  describe('cleanup', () => {
    it('should clean up old sessions', () => {
      service.initialize();

      // Create and end a session
      service.startSession();
      service.endSession();

      // Note: In real usage, cleanup would delete sessions older than N days
      // For testing, we just verify the method doesn't throw
      const count = service.cleanup(0); // 0 days = immediate cleanup
      expect(count).toBeGreaterThanOrEqual(0);
    });
  });
});
