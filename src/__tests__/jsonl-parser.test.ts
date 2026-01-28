import { describe, it, expect, vi } from 'vitest';
import {
  parseJsonlLine,
  createJsonlParser,
  extractText,
  hasToolUse,
  getToolNames,
  isComplete,
  extractPrUrl,
  extractPrNumber,
  isApiError,
  isReviewComplete,
  parsePrFromOutput,
} from '../jsonl-parser.js';
import type { ClaudeMessage } from '../types.js';

describe('jsonl-parser', () => {
  describe('parseJsonlLine', () => {
    it('should parse valid JSON', () => {
      const line = '{"type":"assistant","message":{"role":"assistant"}}';
      const result = parseJsonlLine(line);
      expect(result).toEqual({ type: 'assistant', message: { role: 'assistant' } });
    });

    it('should return null for empty lines', () => {
      expect(parseJsonlLine('')).toBeNull();
      expect(parseJsonlLine('   ')).toBeNull();
    });

    it('should return null for invalid JSON', () => {
      expect(parseJsonlLine('not json')).toBeNull();
      expect(parseJsonlLine('{invalid}')).toBeNull();
    });
  });

  describe('createJsonlParser', () => {
    it('should parse complete lines', () => {
      const messages: ClaudeMessage[] = [];
      const parser = createJsonlParser((msg) => messages.push(msg));

      parser.write('{"type":"system"}\n');
      parser.write('{"type":"human"}\n');

      expect(messages).toHaveLength(2);
      expect(messages[0].type).toBe('system');
      expect(messages[1].type).toBe('human');
    });

    it('should handle partial lines across chunks', () => {
      const messages: ClaudeMessage[] = [];
      const parser = createJsonlParser((msg) => messages.push(msg));

      parser.write('{"type":');
      parser.write('"assistant"}\n');

      expect(messages).toHaveLength(1);
      expect(messages[0].type).toBe('assistant');
    });

    it('should flush remaining buffer', () => {
      const messages: ClaudeMessage[] = [];
      const parser = createJsonlParser((msg) => messages.push(msg));

      parser.write('{"type":"result"}');
      expect(messages).toHaveLength(0);

      parser.flush();
      expect(messages).toHaveLength(1);
    });

    it('should call onError for invalid JSON', () => {
      const errors: { error: Error; line: string }[] = [];
      const parser = createJsonlParser(
        () => {},
        (error, line) => errors.push({ error, line })
      );

      parser.write('invalid json\n');

      expect(errors).toHaveLength(1);
      expect(errors[0].line).toBe('invalid json');
    });
  });

  describe('extractText', () => {
    it('should extract text from assistant message', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'text', text: 'Hello ' },
            { type: 'text', text: 'World' },
          ],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(extractText(message)).toBe('Hello \nWorld');
    });

    it('should return empty string for non-assistant messages', () => {
      const message: ClaudeMessage = { type: 'system' };
      expect(extractText(message)).toBe('');
    });

    it('should ignore non-text blocks', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'text', text: 'Hello' },
            { type: 'tool_use', id: 't1', name: 'Read', input: {} },
          ],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(extractText(message)).toBe('Hello');
    });
  });

  describe('hasToolUse', () => {
    it('should detect tool use', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'tool_use', id: 't1', name: 'Read', input: {} },
          ],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(hasToolUse(message)).toBe(true);
    });

    it('should return false without tool use', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'text', text: 'Hello' }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(hasToolUse(message)).toBe(false);
    });
  });

  describe('getToolNames', () => {
    it('should extract tool names', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'tool_use', id: 't1', name: 'Read', input: {} },
            { type: 'tool_use', id: 't2', name: 'Write', input: {} },
          ],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(getToolNames(message)).toEqual(['Read', 'Write']);
    });
  });

  describe('isComplete', () => {
    it('should detect result message as complete', () => {
      const message: ClaudeMessage = {
        type: 'result',
        result: {
          duration_ms: 1000,
          duration_api_ms: 900,
          is_error: false,
          num_turns: 1,
          session_id: 's1',
          total_cost_usd: 0.01,
        },
      };

      expect(isComplete(message)).toBe(true);
    });

    it('should detect end_turn as complete', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [],
          model: 'claude-3',
          stop_reason: 'end_turn',
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(isComplete(message)).toBe(true);
    });
  });

  describe('extractPrUrl', () => {
    it('should extract PR URL from text', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'text', text: 'Created PR: https://github.com/owner/repo/pull/123' },
          ],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(extractPrUrl(message)).toBe('https://github.com/owner/repo/pull/123');
    });

    it('should return null if no PR URL', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'text', text: 'No PR here' }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(extractPrUrl(message)).toBeNull();
    });
  });

  describe('extractPrNumber', () => {
    it('should extract PR number', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'text', text: 'PR: https://github.com/owner/repo/pull/456' },
          ],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(extractPrNumber(message)).toBe(456);
    });
  });

  describe('isApiError', () => {
    it('should detect API error in result', () => {
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

      expect(isApiError(message)).toBe(true);
    });

    it('should detect API error in text', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'text', text: 'API rate limit exceeded' }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(isApiError(message)).toBe(true);
    });
  });

  describe('isReviewComplete', () => {
    it('should detect passed review', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'text', text: 'QA GUARDIAN REVIEW\nRESULT: PASS' }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(isReviewComplete(message)).toBe('passed');
    });

    it('should detect failed review', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'text', text: 'RESULT: FAIL - issues found' }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(isReviewComplete(message)).toBe('failed');
    });

    it('should return null for non-review messages', () => {
      const message: ClaudeMessage = {
        type: 'assistant',
        message: {
          id: '1',
          type: 'message',
          role: 'assistant',
          content: [{ type: 'text', text: 'Just working...' }],
          model: 'claude-3',
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 5 },
        },
      };

      expect(isReviewComplete(message)).toBeNull();
    });
  });

  describe('parsePrFromOutput', () => {
    it('should parse PR from accumulated output', () => {
      const output = `
        Working on task...
        Created PR: https://github.com/myorg/myrepo/pull/789
        Done!
      `;

      const result = parsePrFromOutput(output);
      expect(result).toEqual({
        number: 789,
        url: 'https://github.com/myorg/myrepo/pull/789',
      });
    });

    it('should return null if no PR in output', () => {
      expect(parsePrFromOutput('No PR here')).toBeNull();
    });
  });
});
