import { describe, it, expect } from 'vitest';
import {
  STATE_TRANSITIONS,
  isValidTransition,
  detectStateFromMessage,
  detectStateFromOutput,
  isTerminalState,
  needsIntervention,
  getStateDescription,
  getStateEmoji,
  getAvailableActions,
} from '../state-machine.js';
import type { WorkerState, WorkerInstance, ClaudeMessage } from '../types.js';

describe('state-machine', () => {
  describe('STATE_TRANSITIONS', () => {
    it('should define transitions for all states', () => {
      const states: WorkerState[] = [
        'SPAWNING', 'INITIALIZING', 'WORKING', 'PR_OPEN',
        'REVIEWING', 'MERGING', 'MERGED', 'ERROR', 'STOPPED',
      ];

      for (const state of states) {
        expect(STATE_TRANSITIONS[state]).toBeDefined();
        expect(Array.isArray(STATE_TRANSITIONS[state])).toBe(true);
      }
    });

    it('should have STOPPED as terminal state', () => {
      expect(STATE_TRANSITIONS.STOPPED).toEqual([]);
    });

    it('should allow ERROR recovery', () => {
      expect(STATE_TRANSITIONS.ERROR).toContain('WORKING');
      expect(STATE_TRANSITIONS.ERROR).toContain('STOPPED');
    });
  });

  describe('isValidTransition', () => {
    it('should allow valid transitions', () => {
      expect(isValidTransition('SPAWNING', 'INITIALIZING')).toBe(true);
      expect(isValidTransition('INITIALIZING', 'WORKING')).toBe(true);
      expect(isValidTransition('WORKING', 'PR_OPEN')).toBe(true);
      expect(isValidTransition('PR_OPEN', 'REVIEWING')).toBe(true);
      expect(isValidTransition('MERGING', 'MERGED')).toBe(true);
    });

    it('should reject invalid transitions', () => {
      expect(isValidTransition('SPAWNING', 'MERGED')).toBe(false);
      expect(isValidTransition('WORKING', 'SPAWNING')).toBe(false);
      expect(isValidTransition('STOPPED', 'WORKING')).toBe(false);
    });

    it('should allow any state to transition to ERROR', () => {
      const states: WorkerState[] = [
        'SPAWNING', 'INITIALIZING', 'WORKING', 'PR_OPEN', 'REVIEWING', 'MERGING',
      ];

      for (const state of states) {
        expect(isValidTransition(state, 'ERROR')).toBe(true);
      }
    });
  });

  describe('detectStateFromMessage', () => {
    it('should detect WORKING from tool use', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'tool_use', id: 't1', name: 'Read', input: {} }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(detectStateFromMessage(message, 'INITIALIZING')).toBe('WORKING');
    });

    it('should detect PR_OPEN from PR URL', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'text', text: 'Created https://github.com/org/repo/pull/123' },
          ],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(detectStateFromMessage(message, 'WORKING')).toBe('PR_OPEN');
    });

    it('should detect ERROR from API error', () => {
      const message: ClaudeMessage = {
        type: 'result',
        result: {
          duration_ms: 1000,
          duration_api_ms: 900,
          is_error: true,
          num_turns: 1,
          session_id: 's1',
          total_cost_usd: 0,
        },
      };

      expect(detectStateFromMessage(message, 'WORKING')).toBe('ERROR');
    });

    it('should return null for no state change', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'text', text: 'Just thinking...' }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(detectStateFromMessage(message, 'WORKING')).toBeNull();
    });
  });

  describe('detectStateFromOutput', () => {
    it('should detect PR_OPEN from output', () => {
      const output = 'Created PR https://github.com/org/repo/pull/456';
      expect(detectStateFromOutput(output, 'WORKING')).toBe('PR_OPEN');
    });

    it('should detect MERGED from output', () => {
      const output = 'PR successfully merged';
      expect(detectStateFromOutput(output, 'PR_OPEN')).toBe('MERGED');
    });

    it('should detect ERROR from API error in output', () => {
      const output = 'Claude API error: rate limit';
      expect(detectStateFromOutput(output, 'WORKING')).toBe('ERROR');
    });

    it('should detect WORKING from tool activity', () => {
      const output = 'Reading file...';
      expect(detectStateFromOutput(output, 'INITIALIZING')).toBe('WORKING');
    });

    it('should not re-detect PR_OPEN if already in PR state', () => {
      const output = 'PR https://github.com/org/repo/pull/123 is ready';
      expect(detectStateFromOutput(output, 'PR_OPEN')).toBeNull();
      expect(detectStateFromOutput(output, 'REVIEWING')).toBeNull();
    });
  });

  describe('isTerminalState', () => {
    it('should identify terminal states', () => {
      expect(isTerminalState('STOPPED')).toBe(true);
      expect(isTerminalState('MERGED')).toBe(true);
    });

    it('should identify non-terminal states', () => {
      expect(isTerminalState('SPAWNING')).toBe(false);
      expect(isTerminalState('WORKING')).toBe(false);
      expect(isTerminalState('PR_OPEN')).toBe(false);
      expect(isTerminalState('ERROR')).toBe(false);
    });
  });

  describe('needsIntervention', () => {
    const baseWorker: Omit<WorkerInstance, 'state' | 'lastActivity' | 'error'> = {
      config: {
        id: 'test',
        repoName: 'repo',
        worktreePath: '/path',
        branchName: 'feature/test',
        task: 'test task',
        createdAt: new Date(),
      },
      process: null,
      pid: null,
      prNumber: null,
      prUrl: null,
      reviewStatus: 'none',
      agentsRun: [],
    };

    it('should flag ERROR state for intervention', () => {
      const worker: WorkerInstance = {
        ...baseWorker,
        state: 'ERROR',
        lastActivity: new Date(),
        error: 'Something went wrong',
      };

      const result = needsIntervention(worker);
      expect(result.needed).toBe(true);
      expect(result.action).toBe('restart');
    });

    it('should flag stale WORKING state', () => {
      const staleTime = new Date(Date.now() - 10 * 60 * 1000); // 10 minutes ago
      const worker: WorkerInstance = {
        ...baseWorker,
        state: 'WORKING',
        lastActivity: staleTime,
        error: null,
      };

      const result = needsIntervention(worker);
      expect(result.needed).toBe(true);
      expect(result.action).toBe('nudge');
    });

    it('should not flag recent activity', () => {
      const worker: WorkerInstance = {
        ...baseWorker,
        state: 'WORKING',
        lastActivity: new Date(),
        error: null,
      };

      const result = needsIntervention(worker);
      expect(result.needed).toBe(false);
    });
  });

  describe('getStateDescription', () => {
    it('should return descriptions for all states', () => {
      const states: WorkerState[] = [
        'SPAWNING', 'INITIALIZING', 'WORKING', 'PR_OPEN',
        'REVIEWING', 'MERGING', 'MERGED', 'ERROR', 'STOPPED',
      ];

      for (const state of states) {
        const desc = getStateDescription(state);
        expect(typeof desc).toBe('string');
        expect(desc.length).toBeGreaterThan(0);
      }
    });
  });

  describe('getStateEmoji', () => {
    it('should return emojis for all states', () => {
      const states: WorkerState[] = [
        'SPAWNING', 'INITIALIZING', 'WORKING', 'PR_OPEN',
        'REVIEWING', 'MERGING', 'MERGED', 'ERROR', 'STOPPED',
      ];

      for (const state of states) {
        const emoji = getStateEmoji(state);
        expect(typeof emoji).toBe('string');
        expect(emoji.length).toBeGreaterThan(0);
      }
    });

    it('should use distinct emojis', () => {
      const emojis = new Set([
        getStateEmoji('WORKING'),
        getStateEmoji('PR_OPEN'),
        getStateEmoji('MERGED'),
        getStateEmoji('ERROR'),
      ]);
      expect(emojis.size).toBe(4);
    });
  });

  describe('getAvailableActions', () => {
    it('should return actions for WORKING state', () => {
      const actions = getAvailableActions('WORKING');
      expect(actions).toContain('stop');
      expect(actions).toContain('send');
      expect(actions).toContain('status');
    });

    it('should return actions for PR_OPEN state', () => {
      const actions = getAvailableActions('PR_OPEN');
      expect(actions).toContain('review');
      expect(actions).toContain('merge');
    });

    it('should return cleanup for terminal states', () => {
      expect(getAvailableActions('MERGED')).toContain('cleanup');
      expect(getAvailableActions('STOPPED')).toContain('cleanup');
    });
  });
});
