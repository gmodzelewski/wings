"""Calculator tool: sqrt must not require argument b (3B omits it)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TRACING = REPO_ROOT / "demo" / "agent-tracing"
NOTEBOOKS = REPO_ROOT / "demo" / "notebooks"
sys.path.insert(0, str(TRACING))

from calculator_ops import run_calculator  # noqa: E402

NOTEBOOK_NAMES = (
    "01_agent_tracing_autolog.ipynb",
    "02_eval_improvement.ipynb",
    "03_prod_eval_judges.ipynb",
)


def test_sqrt_without_b_returns_12():
    out = run_calculator("sqrt", 144)
    assert "12" in out


def test_add_with_b():
    out = run_calculator("add", 2, 3)
    assert "5" in out


def test_add_without_b_is_tool_error_not_exception():
    out = run_calculator("add", 2)
    assert "Error" in out


def test_divide_by_zero():
    out = run_calculator("divide", 1, 0)
    assert "Error" in out


def test_notebooks_have_optional_git_pull():
    for name in NOTEBOOK_NAMES:
        blob = "".join(
            "".join(cell.get("source", []))
            for cell in json.loads((NOTEBOOKS / name).read_text())["cells"]
        )
        assert "git pull --ff-only" in blob, name
    """SHOW copies must match the schema the 3B actually emits for sqrt."""
    for name in NOTEBOOK_NAMES:
        blob = "".join(
            "".join(cell.get("source", []))
            for cell in json.loads((NOTEBOOKS / name).read_text())["cells"]
        )
        assert "def calculator(" in blob, name
        assert "b: float | None = None" in blob or "b: Optional[float] = None" in blob, name


def _python_cells(name: str) -> list[str]:
    nb = json.loads((NOTEBOOKS / name).read_text())
    cells = []
    for cell in nb["cells"]:
        if cell.get("cell_type") != "code":
            continue
        src = "".join(cell.get("source", []))
        if any(line.lstrip().startswith(("%", "!")) for line in src.splitlines()):
            continue
        cells.append(src)
    return cells


def test_notebooks_imports_only_at_top_of_first_python_cell():
    """E402: later cells must not import; first python cell keeps imports first."""
    import ast

    for name in NOTEBOOK_NAMES:
        cells = _python_cells(name)
        assert cells, name
        first = ast.parse(cells[0])
        seen_non_import = False
        for node in first.body:
            is_import = isinstance(node, (ast.Import, ast.ImportFrom))
            if is_import and seen_non_import:
                raise AssertionError(f"{name}: import after statements in first cell")
            if not is_import:
                seen_non_import = True
        for i, src in enumerate(cells[1:], start=2):
            tree = ast.parse(src)
            late = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))]
            assert not late, f"{name} python cell {i} has imports (E402 when concatenated)"
