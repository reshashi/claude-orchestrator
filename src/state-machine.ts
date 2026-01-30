/**
 * State Machine
 *
 * Defines valid state transitions and state detection logic.
 * Replaces the regex-based state detection from bash scripts.
 */

import type { WorkerState, WorkerInstance, ClaudeMessage } from './types.js';
import {
  hasToolUse,
  extractPrUrl,
  isApiError,
  isComplete,
  isReviewComplete,
} from './jsonl-parser.js';

/**
 * Valid state transitions
 * Maps current state -> allowed next states
 */
export const STATE_TRANSITIONS: Record<WorkerState, WorkerState[]> = {
  SPAWNING: ['INITIALIZING', 'ERROR', 'STOPPED'],
  INITIALIZING: ['WORKING', 'ERROR', 'STOPPED'],
  WORKING: ['PR_OPEN', 'ERROR', 'STOPPED'],
  PR_OPEN: ['REVIEWING', 'MERGING', 'WORKING', 'ERROR', 'STOPPED'],  // Can go back to WORKING if CI fails
  REVIEWING: ['PR_OPEN', 'MERGING', 'ERROR', 'STOPPED'],  // Back to PR_OPEN if review fails
  MERGING: ['MERGED', 'ERROR', 'STOPPED'],
  MERGED: ['STOPPED'],  // Terminal state (except cleanup)
  ERROR: ['WORKING', 'STOPPED'],  // Can recover from error
  STOPPED: [],  // Terminal state
};

/**
 * Check if a state transition is valid
 */
export function isValidTransition(from: WorkerState, to: WorkerState): boolean {
  return STATE_TRANSITIONS[from]?.includes(to) ?? false;
}

/**
 * Determine worker state from a Claude message
 */
export function detectStateFromMessage(
  message: ClaudeMessage,
  currentState: WorkerState
): WorkerState | null {
  // Check for API errors first
  if (isApiError(message)) {
    return 'ERROR';
  }

  // Check for PR creation
  const prUrl = extractPrUrl(message);
  if (prUrl && currentState !== 'PR_OPEN') {
    return 'PR_OPEN';
  }

  // Check for review completion
  const reviewResult = isReviewComplete(message);
  if (reviewResult === 'passed') {
    return 'MERGING';  // Ready for merge after review passes
  }
  if (reviewResult === 'failed') {
    return 'PR_OPEN';  // Back to PR_OPEN to fix issues
  }

  // Check for tool use (indicates active work)
  if (hasToolUse(message)) {
    if (currentState === 'INITIALIZING') {
      return 'WORKING';
    }
    // Stay in current state if already working
    return null;
  }

  // Check for completion without PR (might be an issue)
  if (isComplete(message) && currentState === 'WORKING') {
    // Don't change state - orchestrator will handle this
    return null;
  }

  return null;
}

/**
 * Detect state from accumulated output text
 * (Fallback for when JSONL parsing doesn't capture everything)
 */
export function detectStateFromOutput(output: string, currentState: WorkerState): WorkerState | null {
  // PR detection
  if (/github\.com\/[^/]+\/[^/]+\/pull\/\d+/.test(output)) {
    if (!['PR_OPEN', 'REVIEWING', 'MERGING', 'MERGED'].includes(currentState)) {
      return 'PR_OPEN';
    }
  }

  // Merged detection
  if (/✓.*merged|PR.*merged|Successfully merged/i.test(output)) {
    return 'MERGED';
  }

  // Error detection (Claude/API errors only, not build errors)
  if (/API.*error|rate.*limit|ECONNREFUSED|Claude.*error/i.test(output)) {
    return 'ERROR';
  }

  // Working detection (tool calls)
  if (/Running|Writing|Reading|Editing|Searching/i.test(output) && currentState === 'INITIALIZING') {
    return 'WORKING';
  }

  return null;
}

/**
 * Check if worker is in a terminal state
 */
export function isTerminalState(state: WorkerState): boolean {
  return state === 'STOPPED' || state === 'MERGED';
}

/**
 * Check if worker needs intervention
 */
export function needsIntervention(worker: WorkerInstance): {
  needed: boolean;
  reason?: string;
  action?: 'nudge' | 'restart' | 'manual';
} {
  const { state, lastActivity, error } = worker;

  // Check for stale worker
  const staleThresholdMs = 5 * 60 * 1000; // 5 minutes
  const isStale = Date.now() - lastActivity.getTime() > staleThresholdMs;

  if (state === 'ERROR') {
    return {
      needed: true,
      reason: error ?? 'Worker in error state',
      action: 'restart',
    };
  }

  if (isStale && state === 'WORKING') {
    return {
      needed: true,
      reason: 'Worker appears stalled (no activity for 5 minutes)',
      action: 'nudge',
    };
  }

  if (isStale && state === 'INITIALIZING') {
    return {
      needed: true,
      reason: 'Worker failed to initialize',
      action: 'restart',
    };
  }

  return { needed: false };
}

/**
 * Get human-readable state description
 */
export function getStateDescription(state: WorkerState): string {
  const descriptions: Record<WorkerState, string> = {
    SPAWNING: 'Starting Claude process...',
    INITIALIZING: 'Claude is loading and reading instructions...',
    WORKING: 'Actively working on task...',
    PR_OPEN: 'Pull request created, awaiting review...',
    REVIEWING: 'QA review in progress...',
    MERGING: 'Merging pull request...',
    MERGED: 'Complete! PR has been merged.',
    ERROR: 'Error encountered - may need intervention.',
    STOPPED: 'Worker has been stopped.',
  };

  return descriptions[state] ?? 'Unknown state';
}

/**
 * Get state emoji for display
 */
export function getStateEmoji(state: WorkerState): string {
  const emojis: Record<WorkerState, string> = {
    SPAWNING: '🚀',
    INITIALIZING: '⏳',
    WORKING: '⚡',
    PR_OPEN: '📝',
    REVIEWING: '🔍',
    MERGING: '🔄',
    MERGED: '✅',
    ERROR: '❌',
    STOPPED: '⏹️',
  };

  return emojis[state] ?? '❓';
}

/**
 * Determine what actions are available for a worker in a given state
 */
export function getAvailableActions(state: WorkerState): string[] {
  const actions: Record<WorkerState, string[]> = {
    SPAWNING: ['stop'],
    INITIALIZING: ['stop', 'send'],
    WORKING: ['stop', 'send', 'status'],
    PR_OPEN: ['stop', 'send', 'review', 'merge'],
    REVIEWING: ['stop', 'status'],
    MERGING: ['status'],
    MERGED: ['cleanup'],
    ERROR: ['restart', 'stop', 'cleanup'],
    STOPPED: ['restart', 'cleanup'],
  };

  return actions[state] ?? [];
}
