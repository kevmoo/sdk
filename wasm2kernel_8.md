# Wasm2Kernel: Milestone 3 - Structured Control Flow

## The Challenge
WebAssembly uses structured control flow with hierarchical blocks (`block`, `loop`, `if`). Branches (`br`, `br_if`) are relative to the depth of these nested blocks. Dart Kernel is also tree-based, but its branching mechanism (`BreakStatement`) targets specific `LabeledStatement` nodes.

## Mapping Strategy

### 1. The Control Stack
During translation, we maintain a `List<ControlFrame> controlStack`.
Each `ControlFrame` tracks:
- The Kernel `Statement` being built (e.g., `Block`, `WhileStatement`, `IfStatement`).
- A `LabeledStatement` that serves as the branch target.
- Wasm depth (the index in the stack).

### 2. Block Mapping
| Wasm | Kernel | Target for `br` |
| :--- | :--- | :--- |
| `block` | `LabeledStatement { Block }` | End of the block. |
| `loop` | `LabeledStatement { WhileStatement(true) { Block } }` | Start of the loop. |
| `if` | `IfStatement` | End of the if/else structure. |

### 3. Branching
- `br n`: Popping `n` frames from the `controlStack` gives us the target `LabeledStatement`.
- Generate a `BreakStatement(target)`.

### 4. Stack Reconciliation
Wasm blocks can consume/produce values on the expression stack. We must ensure that branches and block exits correctly "clean up" or "pass through" these values.

## Initial Target: `factorial.wat`
We will implement `loop`, `br_if`, and `local.set` to pass our recursive factorial test.
