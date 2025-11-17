# Stage 2: Public API

## Objective
Expose mode state through three mechanisms: context keys (already done in Stage 1), query command, and event subscription commands.

## Dependencies
**Requires Stage 1 complete** - Functions `getCurrentMode()`, `notifyModeChange()`, and variable `modeChangeSubscribers` must exist.

## Duration
20-30 minutes

## Changes Overview
- Register 3 new commands in `src/commands.ts`
- Add 3 command metadata entries in `package.json`
- Total: ~33 lines of code

---

## Change 2.1: Register Query Command

**File:** `src/commands.ts`
**Location:** Inside `register()` function, after last command registration (after line 207)
**Lines Added:** ~3

### Context: Existing Command Registration Pattern

Current pattern (lines 186-207):
```typescript
export function register(context: vscode.ExtensionContext) {
    const disposables = [
        vscode.commands.registerCommand("modaledit.toggle", toggle),
        vscode.commands.registerCommand("modaledit.enterNormal", enterNormal),
        vscode.commands.registerCommand("modaledit.enterInsert", enterInsert),
        // ... 15 more commands ...
    ]
    disposables.forEach(disposable => context.subscriptions.push(disposable))
}
```

### Code to Add

Add to the `disposables` array, after the last existing command:

```typescript
        // Mode state query API
        vscode.commands.registerCommand("modaledit.getMode",
            () => getCurrentMode()),
```

**IMPORTANT:** Add comma after previous command, maintain indentation (8 spaces).

### Rationale

**Why arrow function?**
- Matches existing pattern for simple commands (e.g., `toggle`)
- No need for separate function definition (single-line implementation)
- Direct return of `getCurrentMode()` result

**Why no parameters?**
- Query command: just returns current state
- No user input needed
- Simpler API surface

**Why no error handling?**
- `getCurrentMode()` is pure function, cannot fail
- Type-safe return value guaranteed by TypeScript
- If somehow fails, VS Code's command infrastructure handles it

**Return type:**
- TypeScript infers: `'normal' | 'insert' | 'visual' | 'search'`
- Calling extensions get type-safe result
- Example usage:
  ```typescript
  const mode = await vscode.commands.executeCommand<string>('modaledit.getMode');
  // mode is guaranteed to be one of 4 valid strings
  ```

### Testing

```typescript
// In VS Code Extension Development Host console:
vscode.commands.executeCommand('modaledit.getMode').then(console.log);
// Should log: 'normal', 'insert', 'visual', or 'search'

// Toggle modes and verify return value updates:
// 1. Press 'i' (enter insert) → getMode() returns 'insert'
// 2. Press Esc (enter normal) → getMode() returns 'normal'
// 3. Press 'v' (toggle selection) → getMode() returns 'visual'
// 4. Press '/' (start search) → getMode() returns 'search'
```

---

## Change 2.2: Register Event Subscription Commands

**File:** `src/commands.ts`
**Location:** Immediately after Change 2.1 (inside same `disposables` array)
**Lines Added:** ~15

### Code to Add

```typescript
        // Event subscription API for mode change notifications
        vscode.commands.registerCommand("modaledit.subscribeToModeChanges",
            (commandName: string) => {
                // Validate input
                if (typeof commandName === 'string' && commandName.length > 0) {
                    modeChangeSubscribers.add(commandName);
                    return true;
                }
                return false;
            }),

        vscode.commands.registerCommand("modaledit.unsubscribeFromModeChanges",
            (commandName: string) => {
                return modeChangeSubscribers.delete(commandName);
            }),
```

### Rationale

**Why validate input in subscribe?**
- **Fail fast principle**: Catch invalid input immediately
- Prevents empty strings or non-strings in subscriber set
- Returns `false` to signal failure (caller can handle)
- Better than silently accepting invalid input

**Why no validation in unsubscribe?**
- `Set.delete()` is safe with any input (returns false if not found)
- Unnecessary overhead (delete is idempotent)
- Simpler code

**Why return boolean?**
- Caller can check if operation succeeded
- Standard pattern for success/failure signals
- Example usage:
  ```typescript
  const success = await vscode.commands.executeCommand(
      'modaledit.subscribeToModeChanges',
      'myExt.onModeChange'
  );
  if (!success) {
      console.error('Failed to subscribe');
  }
  ```

**Why Set.add() and Set.delete()?**
- `add()`: Automatically handles duplicates (idempotent)
- `delete()`: Returns true if element was present, false otherwise
- Both are O(1) operations
- Natural Set API, no need to wrap

**Why not support unsubscribe-all?**
- YAGNI: No use case for it yet
- Each extension should manage its own subscriptions
- Can add later if needed without breaking changes

### Parameter Type Safety

**TypeScript perspective:**
```typescript
// Type signature (inferred):
subscribeToModeChanges(commandName: string): boolean
unsubscribeFromModeChanges(commandName: string): boolean
```

**Calling from another extension:**
```typescript
// TypeScript knows parameter type
const success = await vscode.commands.executeCommand<boolean>(
    'modaledit.subscribeToModeChanges',
    'myExtension.onModeChange'  // string required
);
```

### Testing

```typescript
// Test 1: Valid subscription
let result = await vscode.commands.executeCommand(
    'modaledit.subscribeToModeChanges',
    'test.onModeChange'
);
console.log('Subscribe result:', result);  // Should be true

// Test 2: Duplicate subscription (should still return true)
result = await vscode.commands.executeCommand(
    'modaledit.subscribeToModeChanges',
    'test.onModeChange'
);
console.log('Duplicate subscribe:', result);  // Should be true

// Test 3: Invalid subscription (empty string)
result = await vscode.commands.executeCommand(
    'modaledit.subscribeToModeChanges',
    ''
);
console.log('Invalid subscribe:', result);  // Should be false

// Test 4: Unsubscribe existing
result = await vscode.commands.executeCommand(
    'modaledit.unsubscribeFromModeChanges',
    'test.onModeChange'
);
console.log('Unsubscribe result:', result);  // Should be true

// Test 5: Unsubscribe non-existent
result = await vscode.commands.executeCommand(
    'modaledit.unsubscribeFromModeChanges',
    'test.onModeChange'
);
console.log('Unsubscribe again:', result);  // Should be false
```

---

## Change 2.3: Add Command Metadata to package.json

**File:** `package.json`
**Location:** Inside `contributes.commands` array (after existing commands, before closing bracket)
**Lines Added:** ~15 (JSON)

### Context: Existing package.json Structure

```json
{
    "contributes": {
        "commands": [
            {
                "command": "modaledit.toggle",
                "title": "Toggle Modal Editing",
                "category": "ModalEdit"
            },
            // ... 17 more existing commands ...
        ]
    }
}
```

### Code to Add

Add these three entries to the `commands` array:

```json
        {
            "command": "modaledit.getMode",
            "title": "Get Current Mode",
            "category": "ModalEdit"
        },
        {
            "command": "modaledit.subscribeToModeChanges",
            "title": "Subscribe to Mode Changes",
            "category": "ModalEdit"
        },
        {
            "command": "modaledit.unsubscribeFromModeChanges",
            "title": "Unsubscribe from Mode Changes",
            "category": "ModalEdit"
        }
```

**IMPORTANT:**
- Add comma after previous command entry
- Maintain JSON formatting (8-space indentation)
- No trailing comma after last new entry

### Rationale

**Why required?**
- VS Code needs metadata to discover commands
- Enables Command Palette listing
- Provides user-friendly titles
- Required for extensions to find commands via `executeCommand()`

**Why these specific titles?**
- Clear, action-oriented (imperative voice)
- Self-documenting (user understands what command does)
- Consistent with existing ModalEdit command titles
- Professional tone

**Why "ModalEdit" category?**
- Groups with other ModalEdit commands in Command Palette
- Consistent with existing commands
- Easy to find: user types "ModalEdit: " and sees all commands

**Why no keybindings?**
- These are API commands (for programmatic use, not user interaction)
- Most users won't call these directly
- Keybindings would clutter user's keymap
- Can add later if requested

**Why no icons?**
- Not needed for API commands
- Icons are for user-facing commands (menus, UI)
- Keeps package.json minimal

### Testing

```bash
# 1. Validate JSON syntax
npm run compile
# Should complete without JSON parse errors

# 2. Verify commands appear in Command Palette
# In VS Code Extension Development Host:
# - Open Command Palette (Cmd+Shift+P / Ctrl+Shift+P)
# - Type "ModalEdit: Get"
# - Should see "ModalEdit: Get Current Mode"
# - Should also see subscribe/unsubscribe commands

# 3. Execute from Command Palette
# - Select "ModalEdit: Get Current Mode"
# - No visible output (command returns value, doesn't show UI)
# - Check Debug Console: no errors

# 4. Verify programmatic access
# In Extension Development Host console:
vscode.commands.getCommands(true).then(cmds => {
    const modalEditCmds = cmds.filter(c => c.startsWith('modaledit.'));
    console.log('ModalEdit commands:', modalEditCmds.length);
    // Should be 21 (18 existing + 3 new)
});
```

---

## Complete Stage 2 Code Summary

### src/commands.ts Changes

Add to `disposables` array in `register()` function (after line 207):

```typescript
        // Mode state query API
        vscode.commands.registerCommand("modaledit.getMode",
            () => getCurrentMode()),

        // Event subscription API for mode change notifications
        vscode.commands.registerCommand("modaledit.subscribeToModeChanges",
            (commandName: string) => {
                if (typeof commandName === 'string' && commandName.length > 0) {
                    modeChangeSubscribers.add(commandName);
                    return true;
                }
                return false;
            }),

        vscode.commands.registerCommand("modaledit.unsubscribeFromModeChanges",
            (commandName: string) => {
                return modeChangeSubscribers.delete(commandName);
            }),
```

### package.json Changes

Add to `contributes.commands` array:

```json
        {
            "command": "modaledit.getMode",
            "title": "Get Current Mode",
            "category": "ModalEdit"
        },
        {
            "command": "modaledit.subscribeToModeChanges",
            "title": "Subscribe to Mode Changes",
            "category": "ModalEdit"
        },
        {
            "command": "modaledit.unsubscribeFromModeChanges",
            "title": "Unsubscribe from Mode Changes",
            "category": "ModalEdit"
        }
```

**Total: 18 lines (TypeScript) + 15 lines (JSON) = 33 lines added**

---

## Verification Steps

### 1. Compilation
```bash
npm run compile
```
- Should complete without errors
- Check for TypeScript errors in `src/commands.ts`
- Check for JSON parse errors in `package.json`

### 2. Extension Loads
```bash
# Launch extension development host
code --extensionDevelopmentPath=$(pwd)
```
- Open Debug Console
- Verify no activation errors
- Check: "Extension 'modaledit' is now active"

### 3. Command Discovery
```typescript
// In Extension Development Host console
vscode.commands.getCommands(true).then(cmds => {
    console.log('modaledit.getMode exists:', cmds.includes('modaledit.getMode'));
    console.log('modaledit.subscribeToModeChanges exists:',
        cmds.includes('modaledit.subscribeToModeChanges'));
    console.log('modaledit.unsubscribeFromModeChanges exists:',
        cmds.includes('modaledit.unsubscribeFromModeChanges'));
});
// All should log: true
```

### 4. Functional Testing

**Test Query Command:**
```typescript
// Get mode in different states
await vscode.commands.executeCommand('modaledit.getMode');  // 'normal'
await vscode.commands.executeCommand('modaledit.enterInsert');
await vscode.commands.executeCommand('modaledit.getMode');  // 'insert'
await vscode.commands.executeCommand('modaledit.toggleSelection');
await vscode.commands.executeCommand('modaledit.getMode');  // 'visual'
await vscode.commands.executeCommand('modaledit.search', {});
await vscode.commands.executeCommand('modaledit.getMode');  // 'search'
```

**Test Event Subscription:**
```typescript
// Create test subscriber
let modeChanges = [];
vscode.commands.registerCommand('test.logModeChange', (mode) => {
    console.log('Mode changed to:', mode);
    modeChanges.push(mode);
});

// Subscribe
await vscode.commands.executeCommand(
    'modaledit.subscribeToModeChanges',
    'test.logModeChange'
);

// Trigger mode changes
await vscode.commands.executeCommand('modaledit.enterInsert');
await vscode.commands.executeCommand('modaledit.enterNormal');

// Verify
console.log('Received mode changes:', modeChanges);
// Should see: ['insert', 'normal']

// Unsubscribe
const wasSubscribed = await vscode.commands.executeCommand(
    'modaledit.unsubscribeFromModeChanges',
    'test.logModeChange'
);
console.log('Was subscribed:', wasSubscribed);  // true

// Trigger more changes (should not be logged)
await vscode.commands.executeCommand('modaledit.toggle');
console.log('After unsubscribe:', modeChanges);
// Should still be: ['insert', 'normal'] (no new entries)
```

### 5. Context Keys Testing

Open DevTools Console (Help → Toggle Developer Tools):

```javascript
// Inspect context keys
vscode.commands.executeCommand('workbench.action.inspectContextKeys');

// Search for 'modaledit' in the inspector
// Should see:
// - modaledit.mode = 'normal' | 'insert' | 'visual' | 'search'
// - modaledit.selecting = true | false
// - modaledit.normal = true | false (existing)
// - modaledit.searching = true | false (existing)

// Toggle modes and verify context keys update in real-time
```

### 6. Integration Testing with Dependent Extension

Create minimal test extension:

```typescript
// test-extension/extension.ts
import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
    // Get initial mode
    vscode.commands.executeCommand('modaledit.getMode').then(mode => {
        console.log('Initial mode:', mode);
    });

    // Subscribe to changes
    vscode.commands.executeCommand(
        'modaledit.subscribeToModeChanges',
        'testExt.onModeChange'
    );

    // Register handler
    context.subscriptions.push(
        vscode.commands.registerCommand('testExt.onModeChange', (mode) => {
            console.log('Mode changed to:', mode);
            vscode.window.showInformationMessage(`ModalEdit mode: ${mode}`);
        })
    );
}
```

**Expected behavior:**
- On activation: logs initial mode
- On mode changes: shows notification with new mode

---

## Common Issues & Solutions

### Issue: "Command 'modaledit.getMode' not found"
**Cause:** package.json not updated or extension not reloaded
**Solution:**
1. Verify command is in package.json `contributes.commands`
2. Reload extension development host (Cmd+R / Ctrl+R)
3. Check Debug Console for activation errors

### Issue: getMode() returns undefined
**Cause:** `getCurrentMode()` function not implemented (Stage 1 incomplete)
**Solution:** Verify Stage 1 changes are present in `src/commands.ts`

### Issue: Subscribe returns false for valid input
**Cause:** TypeScript type mismatch or validation logic error
**Solution:**
- Check parameter type: must be `string`
- Check validation: `typeof commandName === 'string' && commandName.length > 0`
- Add debug logging: `console.log('Subscribe called with:', typeof commandName, commandName)`

### Issue: Subscribers not receiving notifications
**Cause:** Subscriber command not registered or Stage 1 notification logic not working
**Solution:**
1. Verify subscriber command is registered: `vscode.commands.registerCommand('myCmd', ...)`
2. Check `modeChangeSubscribers` set: add debug logging in `notifyModeChange()`
3. Verify mode changes trigger `updateCursorAndStatusBar()` (add logging)

### Issue: Context keys not updating
**Cause:** `notifyModeChange()` not being called or `setContext` failing
**Solution:**
1. Add logging at start of `notifyModeChange()`
2. Check for errors in try-catch block
3. Verify `vscode.commands.executeCommand('setContext', ...)` is being called

---

## Public API Contract (Finalized)

### Commands

**`modaledit.getMode`**
- **Parameters:** None
- **Returns:** `'normal' | 'insert' | 'visual' | 'search'`
- **Description:** Returns current mode synchronously
- **Use cases:** Initial state query, polling, conditional logic

**`modaledit.subscribeToModeChanges`**
- **Parameters:** `commandName: string` - Command to invoke on mode changes
- **Returns:** `boolean` - `true` if subscribed successfully, `false` if invalid input
- **Description:** Register a command to be called when mode changes. The command will receive one argument: the new mode string.
- **Use cases:** Real-time UI updates, event-driven architecture
- **Notes:** Duplicate subscriptions are idempotent (no error, returns true)

**`modaledit.unsubscribeFromModeChanges`**
- **Parameters:** `commandName: string` - Command to unsubscribe
- **Returns:** `boolean` - `true` if was subscribed, `false` if wasn't
- **Description:** Unregister from mode change notifications
- **Use cases:** Cleanup on deactivation, conditional subscription management

### Context Keys

**`modaledit.mode`** (NEW)
- **Type:** `string`
- **Values:** `'normal' | 'insert' | 'visual' | 'search'`
- **Description:** Current mode (single source of truth)
- **Use in when clauses:** `"when": "modaledit.mode == 'normal'"`

**`modaledit.selecting`** (NEW)
- **Type:** `boolean`
- **Values:** `true` (visual mode) or `false` (other modes)
- **Description:** Convenience shorthand for `modaledit.mode == 'visual'`
- **Use in when clauses:** `"when": "modaledit.selecting"`

**`modaledit.normal`** (EXISTING, UNCHANGED)
- **Type:** `boolean`
- **Values:** `true` (normal/visual/search) or `false` (insert)
- **Description:** True when in modal editing mode (backward compatible)

**`modaledit.searching`** (EXISTING, UNCHANGED)
- **Type:** `boolean`
- **Values:** `true` (search mode) or `false` (other modes)
- **Description:** True when in incremental search mode (backward compatible)

---

## Next Steps

Once Stage 2 is complete and verified:
- ✅ Public API is exposed and functional
- ✅ Commands are discoverable in Command Palette
- ✅ Context keys update in real-time
- ✅ Event subscription system works
- ✅ API contract is stable (can't change without breaking dependents)

**Proceed to Stage 3:** Add comprehensive documentation and finalize testing protocol
