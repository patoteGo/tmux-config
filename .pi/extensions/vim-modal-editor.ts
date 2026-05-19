import {
  CustomEditor,
  type ExtensionAPI,
  type KeybindingsManager,
} from "@earendil-works/pi-coding-agent";
import type { EditorTheme, TUI } from "@earendil-works/pi-tui";
import { matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

type Mode = "normal" | "insert";
type Pending = "g" | "d" | "c" | undefined;
type Motion = "left" | "right" | "up" | "down" | "lineStart" | "lineEnd" | "wordLeft" | "wordRight";
type DeleteOp = "char" | "wordForward" | "wordBackward" | "lineStart" | "lineEnd" | "paste";

const KEY = {
  left: "\x1b[D",
  down: "\x1b[B",
  up: "\x1b[A",
  right: "\x1b[C",
  lineStart: "\x01",
  lineEnd: "\x05",
  wordLeft: "\x1bb",
  wordRight: "\x1bf",
  deleteForward: "\x1b[3~",
  deleteWordBackward: "\x17",
  deleteWordForward: "\x1bd",
  deleteLineStart: "\x15",
  deleteLineEnd: "\x0b",
  yankPaste: "\x19",
  undo: "\x1f",
  newLine: "\x1b[13;2u",
} as const;

class VimModalEditor extends CustomEditor {
  private mode: Mode = "insert";
  private pending: Pending;

  constructor(tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager) {
    super(tui, theme, keybindings);
  }

  private rerender(): void {
    this.tui.requestRender();
  }

  private clearPending(): void {
    this.pending = undefined;
  }

  private setMode(mode: Mode): void {
    this.mode = mode;
    this.clearPending();
    this.rerender();
  }

  private send(seq: string): void {
    super.handleInput(seq);
  }

  private move(motion: Motion): void {
    switch (motion) {
      case "left": this.send(KEY.left); break;
      case "right": this.send(KEY.right); break;
      case "up": this.send(KEY.up); break;
      case "down": this.send(KEY.down); break;
      case "lineStart": this.send(KEY.lineStart); break;
      case "lineEnd": this.send(KEY.lineEnd); break;
      case "wordLeft": this.send(KEY.wordLeft); break;
      case "wordRight": this.send(KEY.wordRight); break;
    }
  }

  private del(op: DeleteOp): void {
    switch (op) {
      case "char": this.send(KEY.deleteForward); break;
      case "wordBackward": this.send(KEY.deleteWordBackward); break;
      case "wordForward": this.send(KEY.deleteWordForward); break;
      case "lineStart": this.send(KEY.deleteLineStart); break;
      case "lineEnd": this.send(KEY.deleteLineEnd); break;
      case "paste": this.send(KEY.yankPaste); break;
    }
  }

  private motionFor(data: string): Motion | undefined {
    switch (data) {
      case "h": return "left";
      case "j": return "down";
      case "k": return "up";
      case "l": return "right";
      case "0":
      case "^": return "lineStart";
      case "$": return "lineEnd";
      case "w":
      case "e": return "wordRight";
      case "b":
      case "g": return "wordLeft";
      default: return undefined;
    }
  }

  private handleNormalMotion(data: string): boolean {
    if (data === "x") {
      this.del("char");
      return true;
    }

    const motion = this.motionFor(data);
    if (!motion) return false;
    this.move(motion);
    return true;
  }

  private handlePending(data: string): boolean {
    if (!this.pending) return false;

    const pending = this.pending;
    this.clearPending();

    if (pending === "g") {
      if (data === "g") {
        this.move("lineStart");
        this.rerender();
        return true;
      }
      if (data === "e") {
        this.move("wordLeft");
        this.rerender();
        return true;
      }
      this.rerender();
      return this.handleNormalMotion(data);
    }

    if (pending === "d") {
      if (data === "d") {
        this.del("lineStart");
        this.del("lineEnd");
        this.rerender();
        return true;
      }
      if (data === "w" || data === "e") {
        this.del("wordForward");
        this.rerender();
        return true;
      }
      if (data === "b") {
        this.del("wordBackward");
        this.rerender();
        return true;
      }
      if (data === "$") {
        this.del("lineEnd");
        this.rerender();
        return true;
      }
      this.rerender();
      return this.handleNormalMotion(data);
    }

    if (pending === "c") {
      if (data === "c") {
        this.del("lineStart");
        this.del("lineEnd");
        this.setMode("insert");
        return true;
      }
      if (data === "w" || data === "e") {
        this.del("wordForward");
        this.setMode("insert");
        return true;
      }
      if (data === "b") {
        this.del("wordBackward");
        this.setMode("insert");
        return true;
      }
      if (data === "$") {
        this.del("lineEnd");
        this.setMode("insert");
        return true;
      }
      this.rerender();
      return this.handleNormalMotion(data);
    }

    return false;
  }

  handleInput(data: string): void {
    if (matchesKey(data, "escape")) {
      if (this.mode === "insert") {
        this.setMode("normal");
        return;
      }
      this.clearPending();
      this.rerender();
      super.handleInput(data);
      return;
    }

    if (this.mode === "insert") {
      super.handleInput(data);
      return;
    }

    if (this.handlePending(data)) return;

    switch (data) {
      case "i": this.setMode("insert"); return;
      case "a": this.move("right"); this.setMode("insert"); return;
      case "I": this.move("lineStart"); this.setMode("insert"); return;
      case "A": this.move("lineEnd"); this.setMode("insert"); return;
      case "o": this.move("lineEnd"); this.send(KEY.newLine); this.setMode("insert"); return;
      case "O": this.move("lineStart"); this.send(KEY.newLine); this.move("up"); this.setMode("insert"); return;
      case "p": this.del("paste"); return;
      case "u": this.send(KEY.undo); return;
      case "D": this.del("lineEnd"); return;
      case "C": this.del("lineEnd"); this.setMode("insert"); return;
      case "g": this.pending = "g"; this.rerender(); return;
      case "d": this.pending = "d"; this.rerender(); return;
      case "c": this.pending = "c"; this.rerender(); return;
      default:
        if (this.handleNormalMotion(data)) return;
    }

    if (data.length === 1 && data.charCodeAt(0) >= 32) return;
    super.handleInput(data);
  }

  render(width: number): string[] {
    const lines = super.render(width);
    if (lines.length === 0) return lines;

    const mode = this.mode === "normal" ? " NORMAL " : " INSERT ";
    const pending = this.pending ? ` ${this.pending}` : "";
    const label = `${mode}${pending}`;
    const last = lines.length - 1;

    if (visibleWidth(lines[last]!) >= label.length) {
      lines[last] = truncateToWidth(lines[last]!, width - label.length, "") + label;
    }

    return lines;
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setEditorComponent((tui, theme, keybindings) => new VimModalEditor(tui, theme, keybindings));
  });
}
