import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';

import { StateManager } from '../state-manager.js';
import { createSilentLogger } from '../logger.js';
import type { WorkerInstance, PersistedWorkerState } from '../types.js';

describe('StateManager', () => {
  let stateManager: StateManager;
  let tempDir: string;

  beforeEach(async () => {
    // Create temp directory for tests
    tempDir = path.join(os.tmpdir(), `orchestrator-test-${Date.now()}`);
    await fs.mkdir(tempDir, { recursive: true });

    stateManager = new StateManager({
      workersDir: tempDir,
      logger: createSilentLogger(),
    });

    await stateManager.initialize();
  });

  afterEach(async () => {
    // Clean up temp directory
    await fs.rm(tempDir, { recursive: true, force: true });
  });

  describe('initialize', () => {
    it('should create workers directory', async () => {
      const stats = await fs.stat(tempDir);
      expect(stats.isDirectory()).toBe(true);
    });

    it('should create registry file', async () => {
      const registryPath = path.join(tempDir, 'registry.json');
      const stats = await fs.stat(registryPath);
      expect(stats.isFile()).toBe(true);
    });
  });

  describe('loadRegistry', () => {
    it('should load empty registry initially', async () => {
      const registry = await stateManager.loadRegistry();
      expect(registry.version).toBe(1);
      expect(registry.workers).toEqual({});
    });
  });

  describe('saveWorkerState', () => {
    it('should save worker state to disk', async () => {
      const worker: WorkerInstance = {
        config: {
          id: 'test-worker',
          repoName: 'test-repo',
          worktreePath: '/path/to/worktree',
          branchName: 'feature/test',
          task: 'Test task',
          createdAt: new Date('2024-01-01'),
        },
        state: 'WORKING',
        process: null,
        pid: 12345,
        prNumber: null,
        prUrl: null,
        lastActivity: new Date('2024-01-01T12:00:00Z'),
        error: null,
        reviewStatus: 'none',
        agentsRun: [],
      };

      await stateManager.saveWorkerState(worker);

      // Check state file exists
      const statePath = path.join(tempDir, 'test-worker', 'state.json');
      const content = await fs.readFile(statePath, 'utf-8');
      const saved = JSON.parse(content) as PersistedWorkerState;

      expect(saved.id).toBe('test-worker');
      expect(saved.state).toBe('WORKING');
      expect(saved.pid).toBe(12345);
    });

    it('should update registry', async () => {
      const worker: WorkerInstance = {
        config: {
          id: 'test-worker-2',
          repoName: 'test-repo',
          worktreePath: '/path/to/worktree',
          branchName: 'feature/test',
          task: 'Test task',
          createdAt: new Date(),
        },
        state: 'INITIALIZING',
        process: null,
        pid: null,
        prNumber: null,
        prUrl: null,
        lastActivity: new Date(),
        error: null,
        reviewStatus: 'none',
        agentsRun: [],
      };

      await stateManager.saveWorkerState(worker);

      const registry = await stateManager.loadRegistry();
      expect(registry.workers['test-worker-2']).toBeDefined();
      expect(registry.workers['test-worker-2'].state).toBe('INITIALIZING');
    });
  });

  describe('loadWorkerState', () => {
    it('should load saved worker state', async () => {
      const worker: WorkerInstance = {
        config: {
          id: 'load-test',
          repoName: 'test-repo',
          worktreePath: '/path',
          branchName: 'feature/load-test',
          task: 'Load test',
          createdAt: new Date(),
        },
        state: 'PR_OPEN',
        process: null,
        pid: 999,
        prNumber: 42,
        prUrl: 'https://github.com/org/repo/pull/42',
        lastActivity: new Date(),
        error: null,
        reviewStatus: 'pending',
        agentsRun: ['qa', 'security'],
      };

      await stateManager.saveWorkerState(worker);
      const loaded = await stateManager.loadWorkerState('load-test');

      expect(loaded).not.toBeNull();
      expect(loaded!.id).toBe('load-test');
      expect(loaded!.state).toBe('PR_OPEN');
      expect(loaded!.prNumber).toBe(42);
      expect(loaded!.reviewStatus).toBe('pending');
      expect(loaded!.agentsRun).toEqual(['qa', 'security']);
    });

    it('should return null for non-existent worker', async () => {
      const loaded = await stateManager.loadWorkerState('non-existent');
      expect(loaded).toBeNull();
    });
  });

  describe('loadAllWorkerStates', () => {
    it('should load all workers from registry', async () => {
      const workers: WorkerInstance[] = [
        {
          config: {
            id: 'worker-1',
            repoName: 'repo',
            worktreePath: '/path/1',
            branchName: 'feature/1',
            task: 'Task 1',
            createdAt: new Date(),
          },
          state: 'WORKING',
          process: null,
          pid: null,
          prNumber: null,
          prUrl: null,
          lastActivity: new Date(),
          error: null,
          reviewStatus: 'none',
          agentsRun: [],
        },
        {
          config: {
            id: 'worker-2',
            repoName: 'repo',
            worktreePath: '/path/2',
            branchName: 'feature/2',
            task: 'Task 2',
            createdAt: new Date(),
          },
          state: 'PR_OPEN',
          process: null,
          pid: null,
          prNumber: 123,
          prUrl: 'https://github.com/org/repo/pull/123',
          lastActivity: new Date(),
          error: null,
          reviewStatus: 'none',
          agentsRun: [],
        },
      ];

      for (const worker of workers) {
        await stateManager.saveWorkerState(worker);
      }

      const all = await stateManager.loadAllWorkerStates();
      expect(all).toHaveLength(2);
      expect(all.map(w => w.id).sort()).toEqual(['worker-1', 'worker-2']);
    });
  });

  describe('removeWorkerState', () => {
    it('should remove worker state from disk', async () => {
      const worker: WorkerInstance = {
        config: {
          id: 'to-remove',
          repoName: 'repo',
          worktreePath: '/path',
          branchName: 'feature/remove',
          task: 'Remove test',
          createdAt: new Date(),
        },
        state: 'MERGED',
        process: null,
        pid: null,
        prNumber: null,
        prUrl: null,
        lastActivity: new Date(),
        error: null,
        reviewStatus: 'none',
        agentsRun: [],
      };

      await stateManager.saveWorkerState(worker);
      await stateManager.removeWorkerState('to-remove');

      const loaded = await stateManager.loadWorkerState('to-remove');
      expect(loaded).toBeNull();

      const registry = await stateManager.loadRegistry();
      expect(registry.workers['to-remove']).toBeUndefined();
    });
  });

  describe('workerExists', () => {
    it('should return true for existing worker', async () => {
      const worker: WorkerInstance = {
        config: {
          id: 'exists-test',
          repoName: 'repo',
          worktreePath: '/path',
          branchName: 'feature/exists',
          task: 'Exists test',
          createdAt: new Date(),
        },
        state: 'WORKING',
        process: null,
        pid: null,
        prNumber: null,
        prUrl: null,
        lastActivity: new Date(),
        error: null,
        reviewStatus: 'none',
        agentsRun: [],
      };

      await stateManager.saveWorkerState(worker);
      expect(await stateManager.workerExists('exists-test')).toBe(true);
    });

    it('should return false for non-existent worker', async () => {
      expect(await stateManager.workerExists('non-existent')).toBe(false);
    });
  });

  describe('getActiveCount', () => {
    it('should count active workers', async () => {
      const workers: WorkerInstance[] = [
        {
          config: { id: 'active-1', repoName: 'r', worktreePath: '/p', branchName: 'b', task: 't', createdAt: new Date() },
          state: 'WORKING',
          process: null, pid: null, prNumber: null, prUrl: null,
          lastActivity: new Date(), error: null, reviewStatus: 'none', agentsRun: [],
        },
        {
          config: { id: 'active-2', repoName: 'r', worktreePath: '/p', branchName: 'b', task: 't', createdAt: new Date() },
          state: 'PR_OPEN',
          process: null, pid: null, prNumber: null, prUrl: null,
          lastActivity: new Date(), error: null, reviewStatus: 'none', agentsRun: [],
        },
        {
          config: { id: 'done-1', repoName: 'r', worktreePath: '/p', branchName: 'b', task: 't', createdAt: new Date() },
          state: 'MERGED',
          process: null, pid: null, prNumber: null, prUrl: null,
          lastActivity: new Date(), error: null, reviewStatus: 'none', agentsRun: [],
        },
        {
          config: { id: 'error-1', repoName: 'r', worktreePath: '/p', branchName: 'b', task: 't', createdAt: new Date() },
          state: 'ERROR',
          process: null, pid: null, prNumber: null, prUrl: null,
          lastActivity: new Date(), error: 'oops', reviewStatus: 'none', agentsRun: [],
        },
      ];

      for (const worker of workers) {
        await stateManager.saveWorkerState(worker);
      }

      const count = await stateManager.getActiveCount();
      expect(count).toBe(2); // WORKING and PR_OPEN
    });
  });

  describe('persistedToInstance', () => {
    it('should convert persisted state to instance', () => {
      const persisted: PersistedWorkerState = {
        id: 'convert-test',
        config: {
          id: 'convert-test',
          repoName: 'repo',
          worktreePath: '/path',
          branchName: 'feature/convert',
          task: 'Convert test',
          createdAt: new Date('2024-01-01'),
        },
        state: 'WORKING',
        pid: 12345,
        prNumber: null,
        prUrl: null,
        lastActivity: '2024-01-01T12:00:00.000Z',
        error: null,
        reviewStatus: 'none',
        agentsRun: [],
      };

      const instance = stateManager.persistedToInstance(persisted);

      expect(instance.config.id).toBe('convert-test');
      expect(instance.state).toBe('WORKING');
      expect(instance.pid).toBe(12345);
      expect(instance.process).toBeNull();
      expect(instance.lastActivity).toBeInstanceOf(Date);
    });
  });

  describe('appendOutputLog / readOutputLog', () => {
    it('should append and read output', async () => {
      await stateManager.appendOutputLog('output-test', '{"line": 1}');
      await stateManager.appendOutputLog('output-test', '{"line": 2}');
      await stateManager.appendOutputLog('output-test', '{"line": 3}');

      const lines = await stateManager.readOutputLog('output-test');
      expect(lines).toHaveLength(3);
      expect(lines[0]).toBe('{"line": 1}');
      expect(lines[2]).toBe('{"line": 3}');
    });

    it('should limit lines when reading', async () => {
      for (let i = 0; i < 10; i++) {
        await stateManager.appendOutputLog('limit-test', `line ${i}`);
      }

      const lines = await stateManager.readOutputLog('limit-test', 3);
      expect(lines).toHaveLength(3);
      expect(lines[0]).toBe('line 7');
      expect(lines[2]).toBe('line 9');
    });

    it('should return empty array for non-existent worker', async () => {
      const lines = await stateManager.readOutputLog('non-existent');
      expect(lines).toEqual([]);
    });
  });
});
