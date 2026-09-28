#!/usr/bin/env python3
"""Shellcheck the bash `run:` blocks inside composite GitHub Actions.

actionlint only understands GitHub Actions workflow files, so a composite
action's own `runs.steps[].run:` blocks (factory-workflows/.github/actions/*)
never get shellchecked by the workflow-lint job. This script extracts each
bash step's `run:` block into a standalone .sh file, replacing `${{ }}`
expressions and declared `env:` names with placeholder shell variables so
shellcheck can lint the block on its own terms, then runs shellcheck on the
result.
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

import yaml

DEFAULT_GLOB = ".github/actions/*/action.yml"
EXPRESSION_RE = re.compile(r"\$\{\{\s*(.*?)\s*\}\}")


def placeholder_name(expression):
    name = re.sub(r"[^A-Za-z0-9_]", "_", expression).strip("_").upper()
    return f"GHA_{name}" if name else "GHA_EXPR"


def extract_bash_steps(action_path):
    """Return (step_name, script_text) for every bash `run:` step in an action.yml."""
    with open(action_path) as action_file:
        action_doc = yaml.safe_load(action_file)

    steps = ((action_doc or {}).get("runs") or {}).get("steps") or []
    extracted = []
    for index, step in enumerate(steps):
        run_block = step.get("run")
        # A composite action step defaults to bash when `shell` is omitted.
        if run_block is None or step.get("shell", "bash") != "bash":
            continue

        placeholders = set()

        def substitute(match, placeholders=placeholders):
            var_name = placeholder_name(match.group(1))
            placeholders.add(var_name)
            return f"${var_name}"

        body = EXPRESSION_RE.sub(substitute, run_block)
        placeholders.update(step.get("env") or {})

        # export, not a bare assignment: shellcheck's SC2034 ("appears
        # unused") only exempts a variable it can see is exported, and most
        # of these placeholders stand in for step env: vars a subprocess
        # reads from its environment, never referenced by name in the
        # script body itself.
        preamble = "".join(f'export {name}="placeholder"\n' for name in sorted(placeholders))
        script = "#!/usr/bin/env bash\n" + preamble + body
        if not script.endswith("\n"):
            script += "\n"

        step_name = step.get("name", f"step-{index}")
        extracted.append((index, step_name, script))

    return extracted


def write_extracted_scripts(action_files, out_dir):
    written = []
    for action_path in action_files:
        action_name = os.path.basename(os.path.dirname(action_path))
        for index, step_name, script in extract_bash_steps(action_path):
            safe_step = re.sub(r"[^A-Za-z0-9_-]", "_", step_name) or f"step{index}"
            out_path = os.path.join(out_dir, f"{action_name}__{index}__{safe_step}.sh")
            with open(out_path, "w") as out_file:
                out_file.write(script)
            written.append(out_path)
    return written


def main():
    pattern = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_GLOB
    action_files = sorted(glob.glob(pattern))
    if not action_files:
        print(f"no composite action files matched: {pattern}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as tmp_dir:
        written = write_extracted_scripts(action_files, tmp_dir)
        if not written:
            # Matched action files but extracted nothing: the point of this
            # job is to close a shellcheck blind spot, so silently passing
            # here would reopen exactly the gap it exists to catch (e.g. a
            # schema change or a step switching away from `shell: bash`).
            print(
                "error: matched composite action files but extracted no bash "
                "run: blocks; this job exists to shellcheck those blocks, so "
                "extracting none is a failure, not a pass",
                file=sys.stderr,
            )
            return 1

        result = subprocess.run(["shellcheck", "--severity=warning", *written])
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
