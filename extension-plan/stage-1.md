# Stage 1: Internal Infrastructure

## Objective
Create internal machinery for mode detection and change notification without exposing any new external API.

## Dependencies
None. Pure internal refactoring of existing code.

## Duration
30-45 minutes

## Changes Overview
- Add 2 module-level state variables
- Add 2 core functions (mode computation, notification)
- Modify 1 existing function (mode change detection)
- Total: ~35 lines of code

---

## Change 1.1: Add State Management Variables

**File:** `src/commands.ts`
**Location:** After line 180 (after existing state variables: `normalMode`, `selecting`, `searching`)
**Lines Added:** ~10

### Code to Add

```typescript
/**
 * Mode change subscriber registry for event notifications.
 * Contains command names to invoke when mode changes.
 */
let modeChangeSubscribers: Set<string> = new Set();

/**
 * Cache of last known mode to detect changes.
 * Initialized to 'normal' to match default normalMode = true.
 */
let currentModeCache: string = 'normal';
```

### Rationale

**Why Set<string>?**
- O(1) add/remove/check operations
- Natural deduplication (same subscriber can't register twice)
- Efficient iteration for notifications

**Why cache the mode?**
- Prevents redundant notifications when `updateCursorAndStatusBar()` is called multiple times without actual mode change
- Important for performance: status bar updates are frequent

**Why initialize to 'normal'?**
- Matches default state: `normalMode = true` (line 134)
- Ensures first actual mode change is detected correctly

### Testing

```typescript
// Verify variables exist
console.log('Subscribers:', modeChangeSubscribers);  // Set(0) {}
console.log('Cache:', currentModeCache);             // 'normal'
```

---

## Change 1.2: Add Core Mode Detection Function

**File:** `src/commands.ts`
**Location:** Immediately after Change 1.1 (around line 190)
**Lines Added:** ~10

### Code to Add

```typescript
/**
 * Single source of truth for current mode computation.
 * Derives mode from existing state variables without side effects.
 *
 * Priority order (highest to lowest):
 * 1. SEARCH - Temporary overlay mode
 * 2. VISUAL - Selection active in normal mode
 * 3. NORMAL - Default modal editing mode
 * 4. INSERT - Standard VS Code editing mode
 *
 * @returns Current mode as one of: 'normal', 'insert', 'visual', 'search'
 */
function getCurrentMode(): 'normal' | 'insert' | 'visual' | 'search' {
    if (searching) return 'search';
    if (normalMode && isSelecting()) return 'visual';
    if (normalMode) return 'normal';
    return 'insert';
}
```

### Rationale

**Why this priority order?**
- Matches existing status bar logic in `updateCursorAndStatusBar()` (lines 354-362):
  ```typescript
  let [style, text, color] =
      searching ? actions.getSearchStyles() :
          isSelecting() && normalMode ? actions.getSelectStyles() :
              normalMode ? actions.getNormalStyles() :
                  actions.getInsertStyles()
  ```
- Search is temporary overlay that takes highest priority
- Visual mode only makes sense in normal mode
- Normal vs Insert is the base state

**Why pure function (no side effects)?**
- Easy to test and reason about
- Can be called multiple times without changing state
- Matches functional programming best practices

**Why type-safe return?**
- Compile-time guarantee of valid mode values
- Auto-completion in dependent extensions
- Prevents typos and invalid modes

**Why reuse `isSelecting()`?**
- DRY principle: don't duplicate selection detection logic
- `isSelecting()` already handles hybrid detection (flag + actual selections)
- Maintains consistency with existing behavior

### Testing

```typescript
// Test in different states
console.log('Mode:', getCurrentMode());  // Should match visible UI state

// Trigger mode changes and verify:
// - Insert mode → 'insert'
// - Normal mode → 'normal'
// - Selection in normal → 'visual'
// - Search → 'search'
```

---

## Change 1.3: Add Mode Change Notification Function

**File:** `src/commands.ts`
**Location:** Immediately after Change 1.2 (around line 200)
**Lines Added:** ~18

### Code to Add

```typescript
/**
 * Notify all registered subscribers when mode changes.
 * Updates VS Code context keys and broadcasts to dependent extensions.
 *
 * Defensive design:
 * - Subscriber errors are caught and ignored (fail silently)
 * - Context key updates happen first (before subscriber notifications)
 * - No assumptions about subscriber implementation
 *
 * @param newMode The new mode to broadcast
 */
async function notifyModeChange(newMode: string): Promise<void> {
    // Update primary context key for when clauses
    await vscode.commands.executeCommand('setContext', 'modaledit.mode', newMode);

    // Update visual mode context key (convenience for keybindings)
    await vscode.commands.executeCommand('setContext', 'modaledit.selecting', newMode === 'visual');

    // Notify all subscribers (fire-and-forget, defensive)
    for (const commandName of modeChangeSubscribers) {
        try {
            await vscode.commands.executeCommand(commandName, newMode);
        } catch {
            // Subscriber may have unloaded, thrown error, or not exist
            // Don't let subscriber errors crash ModalEdit
        }
    }
}
```

### Rationale

**Why async?**
- `executeCommand()` returns a Thenable/Promise
- Proper sequencing: context keys update before subscribers are notified
- Matches existing async patterns in codebase (e.g., `setNormalMode()`, `setSearching()`)

**Why set `modaledit.mode` first?**
- Primary API: single source of truth
- Used in when clauses: `"when": "modaledit.mode == 'normal'"`
- Replaces need for separate boolean context keys per mode

**Why also set `modaledit.selecting`?**
- Convenience for when clauses: easier to write `modaledit.selecting` than `modaledit.mode == 'visual'`
- Consistency: we already have `modaledit.normal` and `modaledit.searching`
- Backward compatible pattern for future users

**Why try-catch in subscriber loop?**
- **Fail fast principle**: Errors should not propagate to ModalEdit
- Subscriber might:
  - Not exist (command name typo)
  - Be unloaded (extension deactivated)
  - Throw error (buggy subscriber code)
  - Return error (invalid implementation)
- Empty catch: Silent failure is acceptable here (subscriber's problem, not ModalEdit's)

**Why for...of instead of forEach?**
- Allows `await` in loop (sequential execution)
- Guarantees order (not critical, but predictable)
- Clearer error handling with try-catch

### Testing

```typescript
// Add test subscriber
modeChangeSubscribers.add('test.onModeChange');

// Trigger notification
await notifyModeChange('normal');

// Verify in DevTools console:
// 1. modaledit.mode is set
// 2. test.onModeChange was called (or error logged if doesn't exist)
```

---

## Change 1.4: Add Mode Change Detection Logic

**File:** `src/commands.ts`
**Location:** End of `updateCursorAndStatusBar()` function (after line 399, before closing brace)
**Lines Added:** ~8

### Context: updateCursorAndStatusBar() Function

This function is the **central update point** for all UI state:
- Called from: `setNormalMode()`, `setSearching()`, `cancelSelection()`, `toggleSelection()`, `enableSelection()`
- Updates: cursor style, status bar text/color
- Already has all state available: `normalMode`, `searching`, `isSelecting()`

**This is the PERFECT place to detect mode changes.**

### Code to Add

```typescript
async function updateCursorAndStatusBar() {
    // ... existing code lines 354-399 ...

    // Detect mode changes and notify subscribers
    const newMode = getCurrentMode();
    if (newMode !== currentModeCache) {
        currentModeCache = newMode;
        // Fire-and-forget notification (don't await to avoid blocking UI updates)
        notifyModeChange(newMode).catch(() => {
            // Notification errors shouldn't crash status bar updates
        });
    }
}
```

### Rationale

**Why at the END of the function?**
- UI updates happen first (cursor, status bar)
- User sees immediate visual feedback
- Mode notification is secondary (don't block UI)

**Why compare with cache?**
- `updateCursorAndStatusBar()` is called frequently (every status bar update)
- Mode doesn't change every time
- Cache prevents redundant notifications and context key updates
- Example: When typing keys in normal mode, status bar shows key sequence but mode stays 'normal'

**Why fire-and-forget (not await)?**
- UI updates should be fast and synchronous-feeling
- Subscriber notifications can be async (they're secondary)
- If we await, slow subscribers would make cursor changes feel laggy

**Why catch errors?**
- Defense in depth: `notifyModeChange()` already has try-catch for subscribers
- This catches errors in `setContext()` commands (rare but possible)
- Errors in notification shouldn't prevent status bar updates

**Why update cache before notifying?**
- Prevents re-entry issues
- If subscriber triggers another mode change, we don't get duplicate notifications
- Cache is already updated before async notification starts

### Testing

```typescript
// Add logging to verify cache working
const newMode = getCurrentMode();
console.log('Mode check:', newMode, 'vs cached:', currentModeCache);
if (newMode !== currentModeCache) {
    console.log('MODE CHANGE DETECTED:', currentModeCache, '→', newMode);
    currentModeCache = newMode;
    notifyModeChange(newMode).catch(() => {});
}

// Expected behavior:
// - First mode change: logs "MODE CHANGE DETECTED"
// - Subsequent calls with same mode: no log (cache hit)
// - Next real mode change: logs again
```

---

## Complete Stage 1 Code Summary

### New Variables (after line 180)
```typescript
let modeChangeSubscribers: Set<string> = new Set();
let currentModeCache: string = 'normal';
```

### New Functions (after line 182)
```typescript
function getCurrentMode(): 'normal' | 'insert' | 'visual' | 'search' {
    if (searching) return 'search';
    if (normalMode && isSelecting()) return 'visual';
    if (normalMode) return 'normal';
    return 'insert';
}

async function notifyModeChange(newMode: string): Promise<void> {
    await vscode.commands.executeCommand('setContext', 'modaledit.mode', newMode);
    await vscode.commands.executeCommand('setContext', 'modaledit.selecting', newMode === 'visual');

    for (const commandName of modeChangeSubscribers) {
        try {
            await vscode.commands.executeCommand(commandName, newMode);
        } catch {}
    }
}
```

### Modified Function (end of updateCursorAndStatusBar, after line 399)
```typescript
    const newMode = getCurrentMode();
    if (newMode !== currentModeCache) {
        currentModeCache = newMode;
        notifyModeChange(newMode).catch(() => {});
    }
```

**Total: 35 lines added**

---

## Verification Steps

### 1. Code Compiles
```bash
npm run compile
```
Should complete with no errors.

### 2. Extension Loads
```bash
# Open extension development host
code --extensionDevelopmentPath=/path/to/vscode-modaledit
```
Check Debug Console for errors.

### 3. Mode Detection Works
Open DevTools Console and run:
```javascript
// Should work after Stage 2 registers the command, but we can test the function directly
// Add temporary logging in getCurrentMode() to verify it's called
```

### 4. No External Changes
- No new commands appear in Command Palette (expected - Stage 2 adds these)
- No context keys visible yet (expected - only set when mode changes)
- Extension behavior unchanged (expected - internal only)

### 5. No Performance Regression
- Toggle modes rapidly (Esc, i, Esc, i, ...)
- Status bar should update instantly (no lag)
- Cursor should change instantly
- No console errors

---

## Common Issues & Solutions

### Issue: TypeScript errors on `getCurrentMode()`
**Cause:** Type narrowing issue with union return type
**Solution:** Explicit return type annotation is required: `: 'normal' | 'insert' | 'visual' | 'search'`

### Issue: `isSelecting()` returns unexpected values
**Cause:** Hybrid detection (flag + actual selections)
**Solution:** This is expected. `isSelecting()` can return true even if `selecting` flag is false, if editor has active selections.

### Issue: `currentModeCache` out of sync
**Cause:** Mode changed without calling `updateCursorAndStatusBar()`
**Solution:** Verify all mode changes eventually call `updateCursorAndStatusBar()`. Should not happen in current code.

### Issue: Notifications fire too frequently
**Cause:** Cache not working, every call triggers notification
**Solution:** Verify cache comparison uses `!==` (strict inequality), and cache is updated before notification.

---

## Next Steps

Once Stage 1 is complete and verified:
- ✅ Mode detection logic is working
- ✅ Event notification infrastructure is ready
- ✅ No external API changes yet (safe to rollback)

**Proceed to Stage 2:** Add public API (command registrations, package.json metadata)
